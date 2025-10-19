open! Core
open! Async

module Config = struct
  type t = { repositories : (string * string) list } [@@deriving sexp]
end
