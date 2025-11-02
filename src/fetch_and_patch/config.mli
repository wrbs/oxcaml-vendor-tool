open! Core
open! Async
open Oxcaml_vendor_tool_lib

type t =
  { dest_dir : string
  ; patches_dir : string option
  }

val load : Project.t -> t Deferred.t
val save : t -> in_:Project.t -> unit Deferred.t
