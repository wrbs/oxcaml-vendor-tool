open! Core
open! Async
open Oxcaml_vendor_tool_lib

module Filter = struct
  type t =
    | Include of Opam.Package.Name.Set.t
    | Exclude of Opam.Package.Name.Set.t
  [@@deriving sexp]
end

module Config = struct
  module Source = struct
    type t = Github of string * string [@@deriving sexp]
  end

  module Repo_config = struct
    type t =
      { source : Source.t
      ; filter : Filter.t option [@sexp.option]
      }
    [@@deriving sexp]
  end

  type t = (Repo.t * Repo_config.t) list [@@deriving sexp]
end

module Resolved_repo = struct
  type t =
    { full_repo : Opam.Url.t
    ; single_file_http : string
    ; filter : Filter.t option [@sexp.option]
    }
  [@@deriving sexp]

  let should_include t package =
    match t.filter with
    | None -> true
    | Some (Include packages) -> Set.mem packages (OpamPackage.name package)
    | Some (Exclude packages) -> not (Set.mem packages (OpamPackage.name package))
  ;;
end

module Resolved_repos = struct
  type t = (Repo.t * Resolved_repo.t) list [@@deriving sexp]

  include Configs.Make (struct
      type nonrec t = t [@@deriving sexp]

      let path = Project.solver_lock_dir ^/ "repos.sexp"
    end)
end

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

let resolve_urls : Config.Source.t -> _ = function
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
    full_repo, single_file_http
;;

let lock (config : Config.t) ~project =
  let%bind repos =
    Deferred.List.map
      config
      ~how:(`Max_concurrent_jobs 32)
      ~f:(fun (name, { source; filter }) ->
        let%map full_repo, single_file_http = resolve_urls source in
        name, { Resolved_repo.full_repo; single_file_http; filter })
  in
  let%map () = Resolved_repos.save repos ~in_:project in
  repos
;;

let sync (repos : Resolved_repos.t) ~project =
  let cache_dir = Project.opam_download_cache project in
  Opam.Par.run_exn
    ~jobs:8
    (List.map repos ~f:(fun (repo, paths) ->
       Opam.Par.job
         ~desc:(Repo.to_string repo)
         (OpamRepository.pull_tree
            ~cache_dir
            ~full_fetch:false
            (Repo.to_string repo)
            (Repo.opam_dir repo ~project)
            []
            [ paths.full_repo ]))
     |> Opam.Par.all_unit)
;;

let lock_and_sync config ~project =
  let%bind repos = lock config ~project in
  sync repos ~project;
  return repos
;;

let sync_only ~project =
  let%bind repos = Resolved_repos.load project in
  sync repos ~project;
  return repos
;;
