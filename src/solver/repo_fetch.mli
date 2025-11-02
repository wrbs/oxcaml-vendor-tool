open! Core
open! Async
open Oxcaml_vendor_tool_lib

module Config : sig
  type t [@@deriving sexp]
end

module Resolved_repos : sig
  module Paths : sig
    type t =
      { full_repo : OpamUrl.t
      ; single_file_http : string
      }
    [@@deriving sexp]
  end

  type t = (Repo.t * Paths.t) list [@@deriving sexp]

  val load : Project.t -> t Deferred.t
  val save : t -> in_:Project.t -> unit Deferred.t
end

val lock_and_sync : Config.t -> project:Project.t -> Resolved_repos.t Deferred.t
val sync_only : project:Project.t -> Resolved_repos.t Deferred.t
