open! Core
open Oxcaml_vendor_tool_lib

type t

include Opam_0install.S.CONTEXT with type t := t

(** [std_env ~arch ~os ~os_distribution ~os_family ~os_version] is an
    environment function that returns the given values for the standard opam
    variables, and [None] for anything else.
    If [opam_version] is not provided, use the version of the linked opam
    library. *)
val std_env
  :  ?ocaml_native:bool
  -> ?sys_ocaml_version:string
  -> ?opam_version:string
  -> arch:string
  -> os:string
  -> os_distribution:string
  -> os_family:string
  -> os_version:string
  -> unit
  -> string
  -> OpamVariable.variable_contents option

val create
  :  ?test:OpamPackage.Name.Set.t
  -> ?pins:(OpamTypes.version * OpamFile.OPAM.t) OpamTypes.name_map
  -> Repo.t list
  -> project:Project.t
  -> constraints:OpamFormula.version_constraint OpamTypes.name_map
  -> env:
       (string
        -> OpamVariable.variable_contents option
       (* see [Opam0install.Dir_context.std_env]*))
  -> t

module Package_source : sig
  type t =
    { repo : Repo.t
    ; version_dir : string
    }
end

val package_source : t -> OpamPackage.t -> Package_source.t
