open! Core

module Vendor_dir = struct
  include
    String_id.Make
      (struct
        let module_name = "Vendor_dir"
      end)
      ()
end

module Hash = struct
  module Kind = struct
    type t =
      | SHA512
      | SHA256
      | MD5
    [@@deriving sexp, compare]
  end

  type t = Kind.t * string [@@deriving sexp, compare]

  let to_opam ((kind, data) : t) =
    match kind with
    | MD5 -> OpamHash.md5 data
    | SHA256 -> OpamHash.sha256 data
    | SHA512 -> OpamHash.sha512 data
  ;;

  let of_opam hash =
    let kind : Kind.t =
      match OpamHash.kind hash with
      | `MD5 -> MD5
      | `SHA256 -> SHA256
      | `SHA512 -> SHA512
    in
    let value = OpamHash.contents hash in
    kind, value
  ;;
end

module Http_source = struct
  type t =
    { url : string
    ; hash : Hash.t
    }
  [@@deriving sexp]

  let compare = Comparable.lift [%compare: Hash.t] ~f:(fun t -> t.hash)
end

module Main_source = struct
  type t =
    | Http of Http_source.t
    | Git of
        { url : string
        ; rev : string
        }
  [@@deriving sexp, compare]
end

module Vendor_dir_config = struct
  type t =
    { source : Main_source.t
    ; extra : Http_source.t String.Map.t
          [@default String.Map.empty] [@sexp_drop_if Map.is_empty]
    ; patches : string list [@sexp.list]
    ; prepare_commands : string list list [@sexp.list]
    }
  [@@deriving sexp]
end

let path = "lock.sexp"

type t = Vendor_dir_config.t Vendor_dir.Map.t [@@deriving sexp]
