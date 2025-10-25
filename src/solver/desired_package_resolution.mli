open! Core
open! Async
open Oxcaml_vendor_tool_lib

val execute
  :  Config.Solver_config.t
  -> project:Project.t
  -> Config.Desired_packages.t Deferred.t

val command : Command.t
