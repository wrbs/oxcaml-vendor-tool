open! Core
open! Async

module type S = sig
  type t [@@deriving sexp]

  val path : string
end

val load : (module S with type t = 'a) -> Project.t -> 'a Deferred.t
val save : (module S with type t = 'a) -> 'a -> in_:Project.t -> unit Deferred.t
val format_sexps : Sexp.t list -> string
