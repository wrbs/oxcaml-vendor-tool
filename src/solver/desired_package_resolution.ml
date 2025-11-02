open! Core
open! Async
open Oxcaml_vendor_tool_lib

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

module Config = struct
  module Statement = struct
    type t =
      | Include_all_matching_version of
          { in_repo : Repo.t
          ; of_ : Opam.Package.Name.t
          }
      | Include of Package_and_constraint.t list
      | Exclude of Opam.Package.Name.t list
    [@@deriving sexp]
  end

  type t = Statement.t list [@@deriving sexp]
end

module Desired_packages = struct
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

  include Configs.Make (struct
      type nonrec t = t [@@deriving sexp]

      let path = Project.solver_lock_dir ^/ "desired-packages.sexp"
    end)
end

let find_packages_matching_version ~in_repo ~of_ ~project =
  return
  @@
  let repo_dir = Repo.opam_dir in_repo ~project in
  let packages = OpamRepository.packages repo_dir in
  let package_versions =
    OpamPackage.Set.to_list packages
    |> List.map ~f:(fun package -> package.name, package.version)
    |> Opam.Package.Name.Map.of_alist_multi
  in
  let target_version =
    Map.find_exn package_versions of_
    |> List.max_elt ~compare:OpamPackage.Version.compare
    |> Option.value_exn
  in
  Map.to_alist package_versions
  |> List.filter_map ~f:(fun (name, versions) ->
    if List.mem versions target_version ~equal:OpamPackage.Version.equal
    then Some (name, Some (Opam.Version_constraint.exact target_version))
    else None)
;;

let execute (config : Config.t) ~project =
  let%bind selected =
    Deferred.List.fold config ~init:Opam.Package.Name.Map.empty ~f:(fun selected spec ->
      let%map op =
        match spec with
        | Include package_and_constraints -> return (`Add package_and_constraints)
        | Exclude packages -> return (`Remove packages)
        | Include_all_matching_version { in_repo; of_ } ->
          let%map to_add = find_packages_matching_version ~in_repo ~of_ ~project in
          `Add to_add
      in
      match op with
      | `Add l ->
        List.fold l ~init:selected ~f:(fun selected (package, constraint_) ->
          Map.set selected ~key:package ~data:constraint_)
      | `Remove l ->
        List.fold l ~init:selected ~f:(fun selected package ->
          Map.remove selected package))
  in
  let%map () = Desired_packages.save selected ~in_:project in
  selected
;;
