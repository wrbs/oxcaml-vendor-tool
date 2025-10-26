open! Core
module Vendor_dir : Identifiable.S

module Hash : sig
  module Kind : sig
    type t =
      | SHA512
      | SHA256
      | MD5
    [@@deriving sexp, compare]
  end

  type t = Kind.t * string [@@deriving sexp, compare]

  val of_opam : OpamHash.t -> t
  val to_opam : t -> OpamHash.t
end

module Http_source : sig
  type t =
    { url : string
    ; hash : Hash.t
    }
  [@@deriving sexp, compare]
end

module Main_source : sig
  type t =
    | Http of Http_source.t
    | Git of
        { url : string
        ; rev : string
        }
  [@@deriving sexp, compare]
end

module Vendor_dir_config : sig
  type t =
    { source : Main_source.t
    ; extra : Http_source.t String.Map.t
          [@default String.Map.empty] [@sexp_drop_if Map.is_empty]
    ; patches : string list [@sexp.list]
    ; prepare_commands : string list list [@sexp.list]
    }
  [@@deriving sexp]
end

val path : string

type t = Vendor_dir_config.t Vendor_dir.Map.t [@@deriving sexp]
