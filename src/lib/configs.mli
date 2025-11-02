open! Core
open! Async

module Make (M : sig
    type t [@@deriving sexp]

    val path : string
  end) : sig
    type t

    val load : Project.t -> t Deferred.t
    val save : t -> in_:Project.t -> unit Deferred.t
  end
  with type t := M.t

val format_sexps : Sexp.t list -> string
