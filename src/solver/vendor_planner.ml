open! Core
open! Async
open Oxcaml_vendor_tool_lib

(* Work out which packages need vendoring

   Work out what to name the dirs
*)

module Disk_package = struct
  type t =
    { package : Opam.Package.t
    ; opam_file : Opam.Opam_file.t
    }
  [@@deriving sexp_of]

  let load_all ~project =
    let package_dir = Project.path project Config.package_dir in
    Sys.ls_dir package_dir
    >>= Deferred.List.filter_map ~how:`Parallel ~f:(fun dirname ->
      let opam_path = package_dir ^/ dirname ^/ "opam" in
      match%bind Sys.file_exists_exn opam_path with
      | false -> return None
      | true ->
        let package = OpamPackage.of_string dirname in
        let%map contents = Reader.file_contents opam_path in
        let opam_file = OpamFile.OPAM.read_from_string contents in
        Some { package; opam_file })
  ;;
end

module Hash = struct
  module Kind = struct
    type t =
      | SHA512
      | SHA256
      | MD5
    [@@deriving sexp, compare]
  end

  type t = Kind.t * string [@@deriving sexp, compare]

  let of_opam hash : t =
    let kind : Kind.t =
      match OpamHash.kind hash with
      | `MD5 -> MD5
      | `SHA256 -> SHA256
      | `SHA512 -> SHA512
    in
    let value = OpamHash.contents hash in
    kind, value
  ;;
end

module Source = struct
  type t =
    { url : Opam.Url.t
    ; hash : Hash.t option
    ; subpath : string option [@sexp.option]
    }
  [@@deriving sexp]

  let of_opam opam_url =
    let url = OpamFile.URL.url opam_url in
    let subpath =
      OpamFile.URL.subpath opam_url |> Option.map ~f:OpamFilename.SubPath.to_string
    in
    let hash =
      OpamFile.URL.checksum opam_url
      |> OpamHash.sort
      |> List.hd
      |> Option.map ~f:Hash.of_opam
    in
    { url; hash; subpath }
  ;;
end

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
  end

  type t = Arg.t Opam.Filtered.t list [@@deriving sexp]

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
  [@@deriving sexp]

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
    ; source : Source.t
    ; repo_basename : string option
    ; extra_files : (string * Hash.t) list [@sexp.list]
    ; extra_sources : (string * Source.t) list [@sexp.list]
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
    let%bind.Option source = OpamFile.OPAM.url package.opam_file >>| Source.of_opam in
    let%map.Option () = Option.some_if (not (should_exclude package ~config)) () in
    let repo_basename =
      OpamFile.OPAM.dev_repo package.opam_file |> Option.bind ~f:extract_repo_basename
    in
    let extra_files =
      OpamFile.OPAM.extra_files package.opam_file
      |> Option.value ~default:[]
      |> List.map ~f:(fun (name, hash) ->
        OpamFilename.Base.to_string name, Hash.of_opam hash)
    in
    let extra_sources =
      OpamFile.OPAM.extra_sources package.opam_file
      |> List.map ~f:(fun (name, url) ->
        OpamFilename.Base.to_string name, Source.of_opam url)
    in
    let patches =
      OpamFile.OPAM.patches package.opam_file
      |> List.map ~f:(Tuple2.map_fst ~f:OpamFilename.Base.to_string)
    in
    let build_steps = OpamFile.OPAM.build package.opam_file |> Build_steps.of_build in
    { package = package.package
    ; source
    ; repo_basename
    ; extra_files
    ; extra_sources
    ; patches
    ; build_steps
    }
  ;;
end

let command =
  Command.async ~summary:"plan how to vendor things based on opam files"
  @@
  let%map_open.Command project = Project.param in
  fun () ->
    let%bind disk_packages = Disk_package.load_all ~project
    and config = Configs.load (module Config.Solver_config) project in
    let includable_packages =
      List.filter_map disk_packages ~f:(Includable_package.of_disk_package_opt ~config)
    in
    List.iter includable_packages ~f:(fun package ->
      print_s [%sexp (package : Includable_package.t)]);
    return ()
;;
