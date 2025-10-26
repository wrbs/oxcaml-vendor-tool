open! Core
open! Async
open Oxcaml_vendor_tool_lib

val upstream_sources_dir : string

val execute
  :  jobs:int
  -> dirs:Lock_file.t
  -> project:Project.t
  -> (unit, unit) Result.t Deferred.t

val command : Command.t

val fetch_and_patch_dir
  :  dest_dir:string Opam.Par.t
  -> vendor_dir:Lock_file.Vendor_dir.t
  -> dir_config:Lock_file.Vendor_dir_config.t
  -> cache_dir:OpamFilename.Dir.t
  -> no_patch:bool
  -> unit Opam.Par.t
