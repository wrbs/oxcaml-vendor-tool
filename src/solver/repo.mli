open! Core
open Oxcaml_vendor_tool_lib

val repos_dir : Project.t -> string

type t = private string

include Identifiable.S with type t := t

val dir : t -> project:Project.t -> string
val opam_dir : t -> project:Project.t -> OpamFilename.Dir.t
