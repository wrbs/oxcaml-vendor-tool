open! Core
open! Async

val cache_dir : string
val solver_lock_dir : string

type t

val root_dir : t -> string
val path : t -> string -> string
val param : t Command.Param.t
val opam_download_cache : t -> OpamFilename.Dir.t
