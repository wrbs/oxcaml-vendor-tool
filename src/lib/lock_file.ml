open! Core

module Hash = struct
  module Kind = struct
    type t =
      | SHA512
      | SHA256
      | MD5
    [@@deriving sexp, compare]
  end

  type t = Kind.t * string [@@deriving sexp, compare]
end

module Source = struct
  type t =
    { url : string
    ; hash : string
    }
  [@@deriving sexp]
end

module Vendor_dir = struct
  type t =
    { dir : string
    ; source : Source.t
    ; extra : Source.t String.Map.t [@sexp.map]
    ; patches : string list [@sexp.list]
    ; prepare_commands : string list list [@sexp.list]
    }
  [@@deriving sexp]
end

module Lock_file = struct
  type t = Vendor_dir.t list
end
