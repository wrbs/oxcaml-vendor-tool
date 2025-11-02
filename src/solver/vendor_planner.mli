open! Core
open! Async
open Oxcaml_vendor_tool_lib

(** Work out which packages need vendoring

   Work out what to name the dirs *)

module Config : sig
  type t [@@deriving sexp]
end

val execute
  :  Config.t
  -> fetched_packages:Solver.Fetched_packages.t
  -> project:Project.t
  -> unit Deferred.t
