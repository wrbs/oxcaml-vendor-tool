open! Core
open! Async
open Oxcaml_vendor_tool_lib

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

let execute (config : Config.Solver_config.t) ~project =
  let%bind selected =
    Deferred.List.fold
      config.package_selection
      ~init:Opam.Package.Name.Map.empty
      ~f:(fun selected spec ->
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
  let%map () = Config.Desired_packages.save selected ~in_:project in
  selected
;;

let command =
  Command.async
    ~summary:
      "decide and lock selected packages from solver-config.sexp and the cached repos"
  @@
  let%map_open.Command project = Project.param in
  fun () ->
    let%bind config = Config.Solver_config.load project in
    let%map _ = execute config ~project in
    ()
;;
