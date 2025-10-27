open! Core
open! Async
open Oxcaml_vendor_tool_lib

val command : Command.t

val fetch_and_patch_dir
  :  dest_dir:string Opam.Par.t
  -> vendor_dir:Lock_file.Vendor_dir.t
  -> dir_config:Lock_file.Vendor_dir_config.t
  -> cache_dir:OpamFilename.Dir.t
  -> no_patch:bool
  -> string Opam.Par.t
