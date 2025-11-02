open! Core
open! Async
open Oxcaml_vendor_tool_lib

val opams_dir : string

module Env : sig
  type t [@@deriving sexp]
end

module Fetched_packages : sig
  module Package_and_dir : sig
    type t =
      { package : OpamPackage.t
      ; version_dir : string option
      }
    [@@deriving sexp]

    val create : package:OpamPackage.t -> version_dir:string -> t
    val version_dir : t -> string
  end

  module Repo_info : sig
    type t =
      { url_prefix : string
      ; packages : Package_and_dir.t list
      }
    [@@deriving sexp]
  end

  type t = (Repo.t * Repo_info.t) list [@@deriving sexp]

  val load : Project.t -> t Deferred.t
  val save : t -> in_:Project.t -> unit Deferred.t
end

val solve_and_sync
  :  env:Env.t
  -> repos:Repo_fetch.Resolved_repos.t
  -> desired_packages:Desired_package_resolution.Desired_packages.t
  -> project:Project.t
  -> Fetched_packages.t Deferred.t
