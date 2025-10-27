open! Core
open Oxcaml_vendor_tool_lib

let main_dir = "_monorepo-solver.lock"
let opams_dir = main_dir ^/ "opams"

module Package_and_constraint = struct
  type t = Opam.Package.Name.t * Opam.Version_constraint.t option

  let sexp_of_t =
    fun (name, constraint_) ->
    match constraint_ with
    | None -> [%sexp (name : Opam.Package.Name.t)]
    | Some (op, version) ->
      [%sexp
        [ (name : Opam.Package.Name.t)
        ; (op : Opam.Relop.t)
        ; (version : Opam.Package.Version.t)
        ]]
  ;;

  let t_of_sexp (sexp : Sexp.t) =
    match sexp with
    | Atom _ -> [%of_sexp: Opam.Package.Name.t] sexp, None
    | List [ n; o; v ] ->
      ( [%of_sexp: Opam.Package.Name.t] n
      , Some ([%of_sexp: Opam.Relop.t] o, [%of_sexp: Opam.Package.Version.t] v) )
    | _ -> of_sexp_error "expected package name, or '(name constraint)'" sexp
  ;;
end

module Repo_source = struct
  type t = Github of string * string [@@deriving sexp]
end

module Solver_config = struct
  let path = "monorepo.solver.sexp"

  module Package_selection = struct
    type t =
      | Include_all_matching_version of
          { in_repo : Repo.t
          ; of_ : Opam.Package.Name.t
          }
      | Include of Package_and_constraint.t list
      | Exclude of Opam.Package.Name.t list
    [@@deriving sexp]
  end

  module Env = struct
    type t =
      { arch : string
      ; os : string
      ; os_distribution : string
      ; os_family : string
      ; os_version : string
      }
    [@@deriving sexp]
  end

  module Vendoring = struct
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

module Repo_paths = struct
  type t =
    { full_repo : Opam.Url.t
    ; single_file_http : string
    }
  [@@deriving sexp]
end

module Repos = struct
  let path = main_dir ^/ "repos.sexp"

  type t = (Repo.t * Repo_paths.t) list [@@deriving sexp]
end

module Desired_packages = struct
  let path = main_dir ^/ "desired-packages.sexp"

  type t = Opam.Version_constraint.t option Opam.Package.Name.Map.t

  module Repr = struct
    type t = { packages : Package_and_constraint.t list } [@@deriving sexp]
  end

  include
    Sexpable.Of_sexpable
      (Repr)
      (struct
        type nonrec t = t

        let to_sexpable t : Repr.t =
          let packages =
            Map.to_alist t
            |> List.stable_sort
                 ~compare:
                   (Comparable.lift [%compare: int] ~f:(function
                      (* sort no-constraints first *)
                      | _, None -> 0
                      | _, Some _ -> 1))
          in
          { packages }
        ;;

        let of_sexpable { Repr.packages } = Opam.Package.Name.Map.of_alist_exn packages
      end)
end

module Fetched_packages = struct
  let path = main_dir ^/ "packages.sexp"

  module Package_and_dir = struct
    type t =
      { package : Opam.Package.t
      ; version_dir : string option
      }

    let sexp_of_t t =
      match t.version_dir with
      | None -> [%sexp (t.package : Opam.Package.t)]
      | Some dir ->
        let name = OpamPackage.name t.package in
        let version = OpamPackage.version t.package in
        [%sexp
          [ (name : Opam.Package.Name.t)
          ; (version : Opam.Package.Version.t)
          ; (dir : string)
          ]]
    ;;

    let t_of_sexp (sexp : Sexp.t) =
      match sexp with
      | List [ name; version; dir ] ->
        { package = [%of_sexp: Opam.Package.t] (List [ name; version ])
        ; version_dir = Some ([%of_sexp: string] dir)
        }
      | _ -> { package = [%of_sexp: Opam.Package.t] sexp; version_dir = None }
    ;;

    let create ~package ~version_dir =
      let version_dir =
        if [%equal: string] version_dir (Opam.Package.to_string package)
        then None
        else Some version_dir
      in
      { package; version_dir }
    ;;

    let version_dir t =
      Option.value_or_thunk t.version_dir ~default:(fun () ->
        OpamPackage.to_string t.package)
    ;;
  end

  module Repo_info = struct
    type t =
      { url_prefix : string
      ; packages : Package_and_dir.t list
      }
    [@@deriving sexp]
  end

  type t = (Repo.t * Repo_info.t) list [@@deriving sexp]
end
