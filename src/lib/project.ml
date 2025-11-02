open! Core
open! Async

let cache_dir = "_cache/monorepo"
let solver_lock_dir = "_monorepo-solver.lock"

type t = { root_dir : string }

let root_dir t = t.root_dir

let path t = function
  | "" -> t.root_dir
  | subpath -> t.root_dir ^/ subpath
;;

let opam_download_cache t = path t (cache_dir ^/ "opam-dl") |> OpamFilename.Dir.of_string

let git_toplevel () =
  let%map output =
    Process.run_exn ~prog:"git" ~args:[ "rev-parse"; "--show-toplevel" ] ()
  in
  String.strip output
;;

let param =
  let%map_open.Command repo_root =
    flag "repo-root" (optional string) ~doc:"(string) path to root dir"
  in
  let unresolved =
    match repo_root with
    | Some x -> x
    | None -> Thread_safe.block_on_async_exn (fun () -> git_toplevel ())
  in
  let root_dir = Filename_unix.realpath unresolved in
  { root_dir }
;;
