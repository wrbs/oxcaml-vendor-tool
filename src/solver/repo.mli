open! Core
open Oxcaml_vendor_tool_lib

val repos_dir : Project.t -> string

type t = private string

include Identifiable.S with type t := t

val dir : t -> project:Project.t -> string
val to_opam : t -> OpamRepositoryName.t
val opam_dir : t -> project:Project.t -> OpamFilename.Dir.t
