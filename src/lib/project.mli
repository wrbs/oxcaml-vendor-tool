open! Core
open! Async

type t

val root_dir : t -> string
val path : t -> string -> string
val param : t Command.Param.t
