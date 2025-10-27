open! Core
open Oxcaml_vendor_tool_lib

val main_dir : string
val opams_dir : string

module Package_and_constraint : sig
  type t = Opam.Package.Name.t * Opam.Version_constraint.t option [@@deriving sexp]
end

module Repo_source : sig
  type t = Github of string * string [@@deriving sexp]
end

module Solver_config : sig
  val path : string

  module Package_selection : sig
    type t =
      | Include_all_matching_version of
          { in_repo : Repo.t
          ; of_ : Opam.Package.Name.t
          }
      | Include of Package_and_constraint.t list
      | Exclude of Opam.Package.Name.t list
    [@@deriving sexp]
  end

  module Env : sig
    type t =
      { arch : string
      ; os : string
      ; os_distribution : string
      ; os_family : string
      ; os_version : string
      }
    [@@deriving sexp]
  end

  module Vendoring : sig
    type t =
      { exclude_pkgs : Opam.Package.Name.Set.t
      ; rename_dirs : string Opam.Package.Name.Map.t
      ; exclude_dirs : Lock_file.Vendor_dir.Set.t
      ; prepare_commands : string list list Lock_file.Vendor_dir.Map.t
      }
    [@@deriving sexp]
  end

  type t =
    { repos : (Repo.t * Repo_source.t) list
    ; package_selection : Package_selection.t list
    ; env : Env.t
    ; vendoring : Vendoring.t
    }
  [@@deriving sexp]
end

module Repo_paths : sig
  type t =
    { full_repo : OpamUrl.t
    ; single_file_http : string
    }
  [@@deriving sexp]
end

module Repos : sig
  val path : string

  type t = (Repo.t * Repo_paths.t) list [@@deriving sexp]
end

module Desired_packages : sig
  val path : string

  type t = Opam.Version_constraint.t option Opam.Package.Name.Map.t [@@deriving sexp]
end

module Fetched_packages : sig
  val path : string

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
end
