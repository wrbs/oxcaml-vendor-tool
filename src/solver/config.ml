open! Core

let main_dir = "_solver"

module Package_and_constraint = struct
  type t = Opam.Package.Name.t * Opam.Version_formula.t option

  let sexp_of_t =
    fun (name, constraint_) ->
    match constraint_ with
    | None -> [%sexp (name : Opam.Package.Name.t)]
    | Some formula ->
      [%sexp [ (name : Opam.Package.Name.t); (formula : Opam.Version_formula.t) ]]
  ;;

  let t_of_sexp (sexp : Sexp.t) =
    match sexp with
    | Atom _ -> [%of_sexp: Opam.Package.Name.t] sexp, None
    | List [ n; f ] ->
      [%of_sexp: Opam.Package.Name.t] n, Some ([%of_sexp: Opam.Version_formula.t] f)
    | _ -> of_sexp_error "expected package name, or '(name constraint)'" sexp
  ;;
end

module Repo_source = struct
  type t = Github of string * string [@@deriving sexp]
end

module Solver_config = struct
  let path = "solver-config.sexp"

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

  type t =
    { repos : (Repo.t * Repo_source.t) list
    ; package_selection : Package_selection.t list
    ; env : Env.t
    }
  [@@deriving sexp]
end

module Repos = struct
  let path = main_dir ^/ "repos.sexp"

  type t = (Repo.t * Opam.Url.t) list [@@deriving sexp]
end

module Desired_packages = struct
  let path = main_dir ^/ "desired-packages.sexp"

  type t = Opam.Version_formula.t option Opam.Package.Name.Map.t

  let sexp_of_t t =
    Sexp.List (Map.to_alist t |> List.map ~f:[%sexp_of: Package_and_constraint.t])
  ;;

  let t_of_sexp (sexp : Sexp.t) =
    match sexp with
    | Atom _ -> of_sexp_error "expected list" sexp
    | List sexps ->
      (match
         List.map sexps ~f:[%of_sexp: Package_and_constraint.t]
         |> Opam.Package.Name.Map.of_alist_or_error
       with
       | Ok x -> x
       | Error error -> raise (Of_sexp_error (Error.to_exn error, sexp)))
  ;;
end
