open! Core
open! Async
open Oxcaml_vendor_tool_lib

module Config : sig
  type t [@@deriving sexp]
end

module Desired_packages : sig
  type t = Opam.Version_constraint.t option Opam.Package.Name.Map.t [@@deriving sexp]

  val load : Project.t -> t Deferred.t
  val save : t -> in_:Project.t -> unit Deferred.t
end

val execute : Config.t -> project:Project.t -> Desired_packages.t Deferred.t
