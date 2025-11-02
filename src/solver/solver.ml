open! Core
open! Async
open Oxcaml_vendor_tool_lib
module Solver = Opam_0install.Solver.Make (Solver_context)

let opams_dir = Project.solver_lock_dir ^/ "opams"

module Env = struct
  type t =
    { arch : string
    ; os : string
    ; os_distribution : string
    ; os_family : string
    ; os_version : string
    }
  [@@deriving sexp]

  let to_fn { arch; os; os_distribution; os_family; os_version } =
    Solver_context.std_env ~arch ~os ~os_distribution ~os_family ~os_version ()
  ;;
end

module Fetched_packages = struct
  module Package_and_dir = struct
    type t =
      { package : Opam.Package.t
      ; version_dir : string option
      }

    let sexp_of_t t =
      match t.version_dir with
      | None -> [%sexp (t.package : Opam.Package.t)]
      | Some dir ->
        let name = OpamPackage.name t.package in
        let version = OpamPackage.version t.package in
        [%sexp
          [ (name : Opam.Package.Name.t)
          ; (version : Opam.Package.Version.t)
          ; (dir : string)
          ]]
    ;;

    let t_of_sexp (sexp : Sexp.t) =
      match sexp with
      | List [ name; version; dir ] ->
        { package = [%of_sexp: Opam.Package.t] (List [ name; version ])
        ; version_dir = Some ([%of_sexp: string] dir)
        }
      | _ -> { package = [%of_sexp: Opam.Package.t] sexp; version_dir = None }
    ;;

    let create ~package ~version_dir =
      let version_dir =
        if [%equal: string] version_dir (Opam.Package.to_string package)
        then None
        else Some version_dir
      in
      { package; version_dir }
    ;;

    let version_dir t =
      Option.value_or_thunk t.version_dir ~default:(fun () ->
        OpamPackage.to_string t.package)
    ;;
  end

  module Repo_info = struct
    type t =
      { url_prefix : string
      ; packages : Package_and_dir.t list
      }
    [@@deriving sexp]
  end

  type t = (Repo.t * Repo_info.t) list [@@deriving sexp]

  include Configs.Make (struct
      type nonrec t = t [@@deriving sexp]

      let path = Project.solver_lock_dir ^/ "packages.sexp"
    end)
end

let solve_packages ~env ~(repos : Repo_fetch.Resolved_repos.t) ~desired_packages ~project =
  let env = Env.to_fn env in
  let constraints =
    Map.to_alist desired_packages
    |> List.filter_map ~f:(fun (name, constraint_) ->
      let%map.Option formula = constraint_ in
      name, formula)
    |> OpamPackage.Name.Map.of_list
  in
  let solver_context = Solver_context.create repos ~project ~constraints ~env in
  let desired_packages = Map.keys desired_packages in
  let%map selections =
    match Solver.solve solver_context desired_packages with
    | Error diagnostics ->
      print_endline (Solver.diagnostics diagnostics);
      exit 1
    | Ok selections -> return selections
  in
  let packages = Solver.packages_of_result selections in
  let repo_summary_alist =
    List.map packages ~f:(fun package ->
      let%tydi { repo; version_dir } =
        Solver_context.package_source solver_context package
      in
      repo, (package, version_dir))
  in
  let repo_packages =
    Repo.Map.of_alist_multi repo_summary_alist
    |> Map.map
         ~f:
           (List.map ~f:(fun (package, version_dir) ->
              Fetched_packages.Package_and_dir.create ~package ~version_dir))
  in
  let repo_summary =
    List.map repos ~f:(fun (repo, { single_file_http; _ }) ->
      let packages = Map.find repo_packages repo |> Option.value ~default:[] in
      repo, { Fetched_packages.Repo_info.url_prefix = single_file_http; packages })
  in
  repo_summary
;;

let solve_and_sync ~env ~repos ~desired_packages ~project =
  let%bind fetched_packages = solve_packages ~env ~repos ~desired_packages ~project in
  let opams_dir = Project.path project opams_dir in
  let%bind () =
    Process.run_expect_no_output_exn ~prog:"rm" ~args:[ "-rf"; opams_dir ] ()
  in
  let%bind () = Unix.mkdir ~p:() opams_dir in
  let to_copy =
    List.concat_map fetched_packages ~f:(fun (repo, { packages; _ }) ->
      let repo_dir = Repo.dir repo ~project in
      List.map packages ~f:(fun package_and_dir ->
        let version_dir = Fetched_packages.Package_and_dir.version_dir package_and_dir in
        let opam_file =
          repo_dir
          ^/ "packages"
          ^/ OpamPackage.name_to_string package_and_dir.package
          ^/ version_dir
          ^/ "opam"
        in
        let dest = opams_dir ^/ [%string "%{version_dir}.opam"] in
        opam_file, dest))
  in
  let%map () =
    Deferred.all_unit
      [ Fetched_packages.save fetched_packages ~in_:project
      ; Deferred.List.iter to_copy ~how:`Parallel ~f:(fun (src, dst) ->
          Process.run_expect_no_output_exn ~prog:"cp" ~args:[ src; dst ] ())
      ]
  in
  fetched_packages
;;
