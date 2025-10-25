open! Core
open! Async
open Oxcaml_vendor_tool_lib

val solve_and_sync
  :  config:Config.Solver_config.t
  -> repos:Config.Repos.t
  -> desired_packages:Config.Desired_packages.t
  -> project:Project.t
  -> unit Deferred.t

val command : Command.t
