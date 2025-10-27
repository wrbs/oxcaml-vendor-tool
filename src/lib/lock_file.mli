open! Core

module Vendor_dir : sig
  type t

  include Identifiable.S with type t := t

  val arg_type : t Command.Arg_type.t
end

module Http_url : sig
  type t [@@deriving sexp]

  val of_string_opt : string -> t option
end

module Http_source : sig
  type t =
    { urls : Http_url.t Nonempty.t
    ; hashes : Opam.Hash.t Nonempty.t
    }
  [@@deriving sexp]

  val of_opam_file : OpamFile.URL.t -> t option

  (** Merge two sources, hashes must overlap *)
  val merge_opt : t -> t -> t option

  val opam_urls : t -> Opam.Url.t list
  val opam_hashes : t -> Opam.Hash.t list
end

module Git_source : sig
  type t =
    { urls : Http_url.t Nonempty.t
    ; commit : string
    }
  [@@deriving sexp]

  (** Merge two sources, commit must be identical *)
  val merge_opt : t -> t -> t option

  val opam_urls : t -> Opam.Url.t list
end

module Main_source : sig
  module Base : sig
    type t =
      | Http of Http_source.t
      | Git of Git_source.t
    [@@deriving sexp]
  end

  type t =
    { base : Base.t
    ; subpath : string option
    }
  [@@deriving sexp]

  val of_opam_file : OpamFile.URL.t -> t option

  (** Merge two sources, base must merge and subpath must be identical *)
  val merge_opt : t -> t -> t option

  val opam_urls : t -> Opam.Url.t list
  val opam_hashes : t -> Opam.Hash.t list
end

module Vendor_dir_config : sig
  type t =
    { provides : Opam.Package.Set.t
    ; source : Main_source.t
    ; extra : Http_source.t String.Map.t
          [@default String.Map.empty] [@sexp_drop_if Map.is_empty]
    ; patches : string list [@sexp.list]
    ; prepare_commands : string list list [@sexp.list]
    }
  [@@deriving sexp]
end

val path : string

type t = Vendor_dir_config.t Vendor_dir.Map.t [@@deriving sexp]
