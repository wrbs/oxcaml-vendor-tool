open! Core
open! Async
open Oxcaml_vendor_tool_lib

module Config = struct
  type t =
    { repos : Repo_fetch.Config.t
    ; package_selection : Desired_package_resolution.Config.t
    ; env : Solver.Env.t
    ; vendoring : Vendor_planner.Config.t
    }
  [@@deriving sexp]

  include Configs.Make (struct
      type nonrec t = t [@@deriving sexp]

      let path = "monorepo.solver.sexp"
    end)
end

let lock_command =
  Command.async ~summary:"refresh and lock the packages to fetch"
  @@
  let%map_open.Command project = Project.param
  and no_update_repos =
    flag "no-update-repos" no_arg ~doc:"keep repos at previous commit revision"
  in
  fun () ->
    let%bind config = Config.load project in
    let%bind repos =
      match no_update_repos with
      | true -> Repo_fetch.sync_only ~project
      | false -> Repo_fetch.lock_and_sync config.repos ~project
    in
    let%bind desired_packages =
      Desired_package_resolution.execute config.package_selection ~project ~repos
    in
    let%bind fetched_packages =
      Solver.solve_and_sync ~env:config.env ~repos ~desired_packages ~project
    in
    let%bind () = Vendor_planner.execute config.vendoring ~fetched_packages ~project in
    return ()
;;

module Phases = struct
  let repo_lock_and_sync =
    Command.async ~summary:"update the cached repos from the solver-config.sexp"
    @@
    let%map_open.Command project = Project.param in
    fun () ->
      let%bind config = Config.load project in
      let%map _repos = Repo_fetch.lock_and_sync config.repos ~project in
      ()
  ;;

  let repo_sync_only =
    Command.async ~summary:"update the cached repos from the solver-config.sexp"
    @@
    let%map_open.Command project = Project.param in
    fun () ->
      let%map _repos = Repo_fetch.sync_only ~project in
      ()
  ;;

  let resolve_desired_packages =
    Command.async
      ~summary:
        "decide and lock selected packages from solver-config.sexp and the cached repos"
    @@
    let%map_open.Command project = Project.param in
    fun () ->
      let%bind config = Config.load project
      and repos = Repo_fetch.Resolved_repos.load project in
      let%map _ =
        Desired_package_resolution.execute config.package_selection ~repos ~project
      in
      ()
  ;;

  let run_solver =
    Command.async
      ~summary:
        "run package solving based on locked repos/package selection and env in \
         solver-config.sexp"
    @@
    let%map_open.Command project = Project.param in
    fun () ->
      let%bind config = Config.load project in
      let%bind repos = Repo_fetch.Resolved_repos.load project in
      let%bind desired_packages =
        Desired_package_resolution.Desired_packages.load project
      in
      Solver.solve_and_sync ~env:config.env ~repos ~desired_packages ~project
      |> Deferred.ignore_m
  ;;

  let vendor_planner =
    Command.async ~summary:"plan how to vendor things based on opam files"
    @@
    let%map_open.Command project = Project.param in
    fun () ->
      let%bind config = Config.load project
      and fetched_packages = Solver.Fetched_packages.load project in
      Vendor_planner.execute config.vendoring ~fetched_packages ~project
  ;;

  let command =
    Command.group
      ~summary:
        "contains commands for phased versions of 'lock', allowing tweaking the outputs \
         between stages"
      [ "repo-lock-and-sync", repo_lock_and_sync
      ; "repo-sync-only", repo_sync_only
      ; "resolve-desired-packages", resolve_desired_packages
      ; "run-solver", run_solver
      ; "vendor-planner", vendor_planner
      ]
  ;;
end

let phases_command = Phases.command
