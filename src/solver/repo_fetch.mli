open! Core
open! Async
open Oxcaml_vendor_tool_lib

val sync_all
  :  Config.Solver_config.t
  -> project:Project.t
  -> update_lock:bool
  -> Config.Repos.t Deferred.t

val lock_and_sync_command : Command.t
val sync_only_command : Command.t
