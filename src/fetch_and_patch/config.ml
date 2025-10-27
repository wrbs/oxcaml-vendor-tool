open! Core

let path = "monorepo.sexp"

type t =
  { dest_dir : string
  ; patches_dir : string option [@sexp.option]
  }
[@@deriving sexp]
