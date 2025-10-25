open! Core
open! Async
open Oxcaml_vendor_tool_lib
module Solver = Opam_0install.Solver.Make (Solver_context)

let get_env (env : Config.Solver_config.Env.t) =
  let%tydi { arch; os; os_distribution; os_family; os_version } = env in
  Solver_context.std_env ~arch ~os ~os_distribution ~os_family ~os_version ()
;;

let solve_packages ~env ~repos ~desired_packages ~project =
  let env = get_env env in
  let repos = List.map repos ~f:Tuple2.get1 in
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
  let package_dirs, repo_summary_alist =
    List.map packages ~f:(fun package ->
      let%tydi { repo; package_dir } =
        Solver_context.package_source solver_context package
      in
      package_dir, (repo, package))
    |> List.unzip
  in
  let repo_summary =
    Repo.Map.of_alist_multi repo_summary_alist |> Map.map ~f:Opam.Package.Set.of_list
  in
  package_dirs, repo_summary
;;

let solve_and_sync ~(config : Config.Solver_config.t) ~repos ~desired_packages ~project =
  let%bind package_dirs, repo_summary =
    solve_packages ~env:config.env ~repos ~desired_packages ~project
  in
  let packages_dir = Project.path project Config.package_dir in
  let%bind () =
    Process.run_expect_no_output_exn ~prog:"rm" ~args:[ "-rf"; packages_dir ] ()
  in
  let%bind () = Unix.mkdir ~p:() packages_dir in
  let summary_path = Project.path project (Config.main_dir ^/ "package-summary.sexp") in
  let summary =
    Map.to_alist repo_summary
    |> List.map ~f:[%sexp_of: Repo.t * Opam.Package.Set.t]
    |> Configs.format_sexps
  in
  Deferred.all_unit
    [ Writer.save summary_path ~contents:summary
    ; Deferred.List.iter package_dirs ~how:`Parallel ~f:(fun package_dir ->
        Process.run_expect_no_output_exn
          ~prog:"cp"
          ~args:[ "-r"; package_dir; packages_dir ]
          ())
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
