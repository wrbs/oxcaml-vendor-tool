open! Core
open! Async
open Oxcaml_vendor_tool_lib

val lock_and_sync
  :  Config.Solver_config.t
  -> project:Project.t
  -> Config.Repos.t Deferred.t

val sync_only : project:Project.t -> Config.Repos.t Deferred.t
