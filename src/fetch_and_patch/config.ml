open! Core
open! Async
open Oxcaml_vendor_tool_lib

type t =
  { dest_dir : string
  ; patches_dir : string option [@sexp.option]
  }
[@@deriving sexp]

include Configs.Make (struct
    type nonrec t = t [@@deriving sexp]

    let path = "monorepo.sexp"
  end)
