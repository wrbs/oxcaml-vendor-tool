open! Core
open! Async
open Oxcaml_vendor_tool_lib

let lock_command =
  Command.async ~summary:"refresh and lock the packages to fetch"
  @@
  let%map_open.Command project = Project.param
  and no_update_repos =
    flag "no-update-repos" no_arg ~doc:"keep repos at previous commit revision"
  in
  fun () ->
    let%bind config = Configs.load (module Config.Solver_config) project in
    let%bind repos =
      Repo_fetch.sync_all config ~project ~update_lock:(not no_update_repos)
    in
    let%bind desired_packages = Desired_package_resolution.execute config ~project in
    let%bind () = Solver.solve_and_sync ~config ~repos ~desired_packages ~project in
    let%bind () = Vendor_planner.execute config ~project in
    return ()
;;

let phases_command =
  Command.group
    ~summary:
      "contains commands for phased versions of 'lock', allowing tweaking the outputs \
       between stages"
    [ "repo-lock-and-sync", Repo_fetch.lock_and_sync_command
    ; "repo-sync-only", Repo_fetch.sync_only_command
    ; "resolve-desired-packages", Desired_package_resolution.command
    ; "run-solver", Solver.command
    ; "vendor-planner", Vendor_planner.command
    ]
;;
