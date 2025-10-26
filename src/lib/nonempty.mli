open! Core

type 'a t = ( :: ) of 'a * 'a list [@@deriving sexp, compare, equal]

val to_list : 'a t -> 'a list
val of_list : 'a list -> 'a t option
val of_list_exn : 'a list -> 'a t
