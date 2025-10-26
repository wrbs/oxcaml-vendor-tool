open! Core
open! Async
open Oxcaml_vendor_tool_lib

(* Work out which packages need vendoring

   Work out what to name the dirs
*)

module Disk_package = struct
  type t =
    { package : Opam.Package.t
    ; repo_url : string
    ; opam_file : Opam.Opam_file.t
    }
  [@@deriving sexp_of]

  let load_all ~project =
    let package_dir = Project.path project Config.package_dir in
    let%bind repos = Configs.load (module Config.Fetched_packages) project in
    List.concat_map repos ~f:(fun (_repo, repo_info) ->
      List.map repo_info.packages ~f:(fun package_and_dir ->
        let package = package_and_dir.package in
        let version_dir =
          Config.Fetched_packages.Package_and_dir.version_dir package_and_dir
        in
        let repo_url =
          repo_info.url_prefix
          ^/ "packages"
          ^/ OpamPackage.name_to_string package
          ^/ version_dir
        in
        let opam_path = package_dir ^/ [%string "%{version_dir}.opam"] in
        let%map contents = Reader.file_contents opam_path in
        let opam_file = OpamFile.OPAM.read_from_string contents in
        { package; repo_url; opam_file }))
    |> Deferred.all
  ;;
end

let hash_of_opam hash : Lock_file.Hash.t =
  let kind : Lock_file.Hash.Kind.t =
    match OpamHash.kind hash with
    | `MD5 -> MD5
    | `SHA256 -> SHA256
    | `SHA512 -> SHA512
  in
  let value = OpamHash.contents hash in
  kind, value
;;

let http_source_of_opam opam_url =
  let url = OpamFile.URL.url opam_url in
  let url =
    match url.backend with
    | `http -> OpamUrl.base_url url
    | _ -> raise_s [%message "Invalid opam url, expected http" (url : Opam.Url.t)]
  in
  let () =
    match OpamFile.URL.subpath opam_url with
    | None -> ()
    | Some subpath ->
      raise_s
        [%message
          "Subpath unexpected"
            (url : string)
            ~subpath:(OpamFilename.SubPath.to_string subpath)]
  in
  let hash =
    OpamFile.URL.checksum opam_url
    |> OpamHash.sort
    |> List.hd
    |> Option.map ~f:hash_of_opam
    |> Option.value_or_thunk ~default:(fun () ->
      raise_s [%message "Hash expected" (url : string)])
  in
  { Lock_file.Http_source.url; hash }
;;

let main_source_of_opam opam_url =
  let url = OpamFile.URL.url opam_url in
  match url.backend with
  | `http -> Lock_file.Main_source.Http (http_source_of_opam opam_url)
  | `git ->
    let repo_url = [%string "%{url.transport}://%{url.path}"] in
    let hash = Option.value_exn url.hash in
    Lock_file.Main_source.Git { url = repo_url; rev = hash }
  | _ -> raise_s [%message "Invalid opam url, expected http or git" (url : Opam.Url.t)]
;;

module Cmd = struct
  module Arg = struct
    type t = OpamTypes.simple_arg

    let sexp_of_t (t : t) =
      match t with
      | CString s -> [%sexp (s : string)]
      | CIdent s -> [%sexp [ (s : string) ]]
    ;;

    let t_of_sexp (sexp : Sexp.t) : t =
      match sexp with
      | Atom s -> CString s
      | List [ Atom s ] -> CIdent s
      | _ -> of_sexp_error "invalid arg" sexp
    ;;

    let compare = Comparable.lift [%compare: Sexp.t] ~f:[%sexp_of: t]
  end

  type t = Arg.t Opam.Filtered.t list [@@deriving sexp, compare]

  let is_dune_build (t : t) =
    match t with
    | (CString "dune", None) :: (CString "build", None) :: _ -> true
    | (CString "env", None) :: _ :: (CString "dune", None) :: (CString "build", None) :: _
      -> true
    | _ -> false
  ;;

  let is_dune_subst (t : t) =
    match t with
    | [ (CString "dune", None); (CString "subst", None) ] -> true
    | _ -> false
  ;;
end

module Build_steps = struct
  type t =
    | Normal_dune
    | Custom of Cmd.t Opam.Filtered.t list
  [@@deriving sexp, compare]

  let of_build (commands : Cmd.t Opam.Filtered.t list) =
    match commands with
    | (a, None) :: _ when Cmd.is_dune_build a -> Normal_dune
    | (a, _) :: (b, None) :: _ when Cmd.is_dune_subst a && Cmd.is_dune_build b ->
      Normal_dune
    | _ -> Custom commands
  ;;
end

module Includable_package = struct
  type t =
    { package : Opam.Package.t
    ; source : Lock_file.Main_source.t
    ; repo_basename : string option
    ; extra : Lock_file.Http_source.t String.Map.t [@sexp.map]
    ; patches : string Opam.Filtered.t list [@sexp.list]
    ; build_steps : Build_steps.t
    }
  [@@deriving sexp]

  let extract_repo_basename url =
    let%bind.Option result =
      Option.try_with (fun () ->
        OpamUrl.base_url url
        |> Uri.of_string
        |> Uri.path
        |> Filename.basename
        |> String.chop_suffix_if_exists ~suffix:".git")
    in
    match result with
    | "." | "" -> None
    | _ -> Some result
  ;;

  let should_exclude (package : Disk_package.t) ~(config : Config.Solver_config.t) =
    let is_excluded =
      Set.mem config.vendoring.exclude (OpamPackage.name package.package)
    in
    let no_build = List.is_empty (OpamFile.OPAM.build package.opam_file) in
    let skip_flags =
      OpamFile.OPAM.flags package.opam_file
      |> List.exists ~f:(function
        | Pkgflag_Compiler | Pkgflag_Conf -> true
        | _ -> false)
    in
    is_excluded || no_build || skip_flags
  ;;

  let of_disk_package_opt (package : Disk_package.t) ~config =
    let open Option.Let_syntax in
    let%bind.Option source =
      OpamFile.OPAM.url package.opam_file >>| main_source_of_opam
    in
    let%map.Option () = Option.some_if (not (should_exclude package ~config)) () in
    let repo_basename =
      OpamFile.OPAM.dev_repo package.opam_file |> Option.bind ~f:extract_repo_basename
    in
    let extra_files =
      OpamFile.OPAM.extra_files package.opam_file
      |> Option.value ~default:[]
      |> List.map ~f:(fun (name, hash) ->
        let url = package.repo_url ^/ "files" ^/ OpamFilename.Base.to_string name in
        let hash = hash_of_opam hash in
        OpamFilename.Base.to_string name, { Lock_file.Http_source.url; hash })
    in
    let extra_sources =
      OpamFile.OPAM.extra_sources package.opam_file
      |> List.map ~f:(fun (name, url) ->
        OpamFilename.Base.to_string name, http_source_of_opam url)
    in
    let patches =
      OpamFile.OPAM.patches package.opam_file
      |> List.map ~f:(Tuple2.map_fst ~f:OpamFilename.Base.to_string)
    in
    let build_steps = OpamFile.OPAM.build package.opam_file |> Build_steps.of_build in
    { package = package.package
    ; source
    ; repo_basename
    ; extra = extra_sources @ extra_files |> String.Map.of_alist_exn
    ; patches
    ; build_steps
    }
  ;;
end

let write_nonstandard_build_packages
      ~(includable_packages : Includable_package.t list)
      ~project
  =
  let sexps =
    List.filter_map includable_packages ~f:(fun pkg ->
      match pkg.build_steps with
      | Normal_dune -> None
      | Custom steps ->
        Some
          [%sexp [ (pkg.package : Opam.Package.t); (steps : Cmd.t Opam.Filtered.t list) ]])
  in
  let contents = Configs.format_sexps sexps in
  let path =
    Project.path project (Config.main_dir ^/ "nonstandard-build-packages.sexp")
  in
  Writer.save path ~contents
;;

module Build_info = struct
  type t =
    { source : Lock_file.Main_source.t
    ; extra : Lock_file.Http_source.t String.Map.t [@sexp.map]
    ; patches : string list [@sexp.list]
    ; build_steps : Build_steps.t
    }
  [@@deriving sexp, compare]
end

let construct_lock_file
      ~(includable_packages : Includable_package.t list)
      ~(config : Config.Solver_config.t)
  =
  let build_info_by_name =
    List.map includable_packages ~f:(fun pkg ->
      let dirname =
        match Map.find config.vendoring.rename_dirs (OpamPackage.name pkg.package) with
        | Some dir -> dir
        | None ->
          (match pkg.repo_basename with
           | None ->
             raise_s
               [%message
                 "Unsure what vendored dir name to use" (pkg.package : Opam.Package.t)]
           | Some s -> s)
      in
      let dir = Lock_file.Vendor_dir.of_string dirname in
      let patches =
        List.map pkg.patches ~f:(fun (patch, filter) ->
          Option.iter filter ~f:(fun filter ->
            raise_s
              [%message
                "Unsure whether to apply patch"
                  (pkg.package : Opam.Package.t)
                  (patch : string)
                  (filter : Opam.Filter.t)]);
          patch)
      in
      let build_info =
        { Build_info.source = pkg.source
        ; extra = pkg.extra
        ; patches
        ; build_steps = pkg.build_steps
        }
      in
      dir, build_info)
    |> Lock_file.Vendor_dir.Map.of_alist_multi
    |> Map.map ~f:(List.dedup_and_sort ~compare:[%compare: Build_info.t])
    |> Map.map ~f:(function
      | [ build_info ] -> build_info
      | options ->
        raise_s
          [%message
            "Conflicting build info for the same dir name, maybe rename one of them"
              (options : Build_info.t list)])
  in
  Map.mapi
    build_info_by_name
    ~f:(fun ~key:dir ~data:{ source; extra; patches; build_steps = _ } ->
      let prepare_commands =
        Map.find config.vendoring.prepare_commands dir |> Option.value ~default:[]
      in
      { Lock_file.Vendor_dir_config.source; extra; patches; prepare_commands })
;;

let execute config ~project =
  let%bind disk_packages = Disk_package.load_all ~project in
  let includable_packages =
    List.filter_map disk_packages ~f:(Includable_package.of_disk_package_opt ~config)
  in
  let%bind () = write_nonstandard_build_packages ~includable_packages ~project in
  let lock_file = construct_lock_file ~includable_packages ~config in
  Configs.save (module Lock_file) lock_file ~in_:project
;;

let command =
  Command.async ~summary:"plan how to vendor things based on opam files"
  @@
  let%map_open.Command project = Project.param in
  fun () ->
    let%bind config = Configs.load (module Config.Solver_config) project in
    execute config ~project
;;
