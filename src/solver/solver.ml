open! Core
open! Async
open Oxcaml_vendor_tool_lib
module Solver = Opam_0install.Solver.Make (Solver_context)

let get_env (env : Config.Solver_config.Env.t) =
  let%tydi { arch; os; os_distribution; os_family; os_version } = env in
  Solver_context.std_env ~arch ~os ~os_distribution ~os_family ~os_version ()
;;

let solve_packages ~env ~(repos : Config.Repos.t) ~desired_packages ~project =
  let env = get_env env in
  let constraints =
    Map.to_alist desired_packages
    |> List.filter_map ~f:(fun (name, constraint_) ->
      let%map.Option formula = constraint_ in
      name, formula)
    |> OpamPackage.Name.Map.of_list
  in
  let solver_context =
    Solver_context.create (List.map repos ~f:Tuple2.get1) ~project ~constraints ~env
  in
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
              Config.Fetched_packages.Package_and_dir.create ~package ~version_dir))
  in
  let repo_summary =
    List.map repos ~f:(fun (repo, { single_file_http; _ }) ->
      let packages = Map.find repo_packages repo |> Option.value ~default:[] in
      repo, { Config.Fetched_packages.Repo_info.url_prefix = single_file_http; packages })
  in
  repo_summary
;;

let solve_and_sync ~(config : Config.Solver_config.t) ~repos ~desired_packages ~project =
  let%bind repo_summary =
    solve_packages ~env:config.env ~repos ~desired_packages ~project
  in
  let packages_dir = Project.path project Config.package_dir in
  let%bind () =
    Process.run_expect_no_output_exn ~prog:"rm" ~args:[ "-rf"; packages_dir ] ()
  in
  let%bind () = Unix.mkdir ~p:() packages_dir in
  let to_copy =
    List.concat_map repo_summary ~f:(fun (repo, { packages; _ }) ->
      let repo_dir = Repo.dir repo ~project in
      List.map packages ~f:(fun package_and_dir ->
        let version_dir =
          Config.Fetched_packages.Package_and_dir.version_dir package_and_dir
        in
        let opam_file =
          repo_dir
          ^/ "packages"
          ^/ OpamPackage.name_to_string package_and_dir.package
          ^/ version_dir
          ^/ "opam"
        in
        let dest = packages_dir ^/ [%string "%{version_dir}.opam"] in
        opam_file, dest))
  in
  Deferred.all_unit
    [ Configs.save (module Config.Fetched_packages) repo_summary ~in_:project
    ; Deferred.List.iter to_copy ~how:`Parallel ~f:(fun (src, dst) ->
        Process.run_expect_no_output_exn ~prog:"cp" ~args:[ src; dst ] ())
    ]
;;

let command =
  Command.async
    ~summary:
      "run package solving based on locked repos/package selection and env in \
       solver-config.sexp"
  @@
  let%map_open.Command project = Project.param in
  fun () ->
    let%bind config = Configs.load (module Config.Solver_config) project in
    let%bind repos = Configs.load (module Config.Repos) project in
    let%bind desired_packages = Configs.load (module Config.Desired_packages) project in
    solve_and_sync ~config ~repos ~desired_packages ~project
;;
