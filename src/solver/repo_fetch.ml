open! Core
open! Async
open Oxcaml_vendor_tool_lib

let get_json url =
  let%bind response, body = Cohttp_async.Client.get (Uri.of_string url) in
  let%map body = Cohttp_async.Body.to_string body in
  match Cohttp.Response.status response with
  | `OK -> Jsonaf.of_string body
  | _ ->
    raise_s
      [%message
        "Unexpected response"
          (url : string)
          (response : Cohttp.Response.t)
          (body : string)]
;;

let get_json_conv url ~(of_json : _ Of_json.t) = get_json url >>| of_json

let resolve_github_ref ~user ~repo ~ref =
  get_json_conv
    [%string "https://api.github.com/repos/%{user}/%{repo}/commits/%{ref}"]
    ~of_json:Of_json.("sha" @. string)
;;

let resolve_source : Config.Repo_source.t -> _ = function
  | Github (user_repo, ref) ->
    let user, repo = String.lsplit2_exn user_repo ~on:'/' in
    let%map sha = resolve_github_ref ~user ~repo ~ref in
    let full_repo =
      { OpamUrl.transport = "https"
      ; path = [%string "github.com/%{user}/%{repo}.git"]
      ; hash = Some sha
      ; backend = `git
      }
    in
    let single_file_http =
      [%string "https://raw.githubusercontent.com/%{user}/%{repo}/%{sha}/"]
    in
    { Config.Repo_paths.full_repo; single_file_http }
;;

let lock (config : Config.Solver_config.t) ~project =
  let%bind repos =
    Deferred.List.map
      config.repos
      ~how:(`Max_concurrent_jobs 32)
      ~f:(fun (name, source) ->
        let%map url = resolve_source source in
        name, url)
  in
  let%map () = Configs.save (module Config.Repos) repos ~in_:project in
  repos
;;

let fetch (repos : Config.Repos.t) ~project =
  let repos_dir = Project.path project "_cache/repos" in
  let%map () = Unix.mkdir ~p:() repos_dir in
  Opam.Par.Compiled.run
    ~jobs:8
    (List.map repos ~f:(fun (repo, paths) ->
       Opam.Par.job
         ~desc:(Repo.to_string repo)
         (OpamRepository.update
            { repo_name = Repo.to_opam repo
            ; repo_url = paths.full_repo
            ; repo_trust = None
            }
            (Repo.opam_dir repo ~project)
          |> Opam.Job.ignore_m))
     |> Opam.Par.all_unit
     |> Opam.Par.compile)
;;

let sync_all config ~project =
  let%bind repos = lock config ~project in
  let%map () = fetch repos ~project in
  repos
;;

let lock_and_sync_command =
  Command.async ~summary:"update the cached repos from the solver-config.sexp"
  @@
  let%map_open.Command project = Project.param in
  fun () ->
    let%bind config = Configs.load (module Config.Solver_config) project in
    let%map _repos = sync_all config ~project in
    ()
;;

let sync_only_command =
  Command.async ~summary:"update the cached repos from the lock file"
  @@
  let%map_open.Command project = Project.param in
  fun () ->
    let%bind repos = Configs.load (module Config.Repos) project in
    fetch repos ~project
;;
