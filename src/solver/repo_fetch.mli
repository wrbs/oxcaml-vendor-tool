open! Core
open! Async
open Oxcaml_vendor_tool_lib

module Filter : sig
  type t =
    | Include of Opam.Package.Name.Set.t
    | Exclude of Opam.Package.Name.Set.t
  [@@deriving sexp]
end

module Config : sig
  type t [@@deriving sexp]
end

module Resolved_repo : sig
  type t =
    { full_repo : OpamUrl.t
    ; single_file_http : string
    ; filter : Filter.t option
    }
  [@@deriving sexp]

  val should_include : t -> Opam.Package.t -> bool
end

module Resolved_repos : sig
  type t = (Repo.t * Resolved_repo.t) list [@@deriving sexp]

  val load : Project.t -> t Deferred.t
  val save : t -> in_:Project.t -> unit Deferred.t
end

val lock_and_sync : Config.t -> project:Project.t -> Resolved_repos.t Deferred.t
val sync_only : project:Project.t -> Resolved_repos.t Deferred.t
