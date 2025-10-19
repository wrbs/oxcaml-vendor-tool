open! Core
open! Async

(* Phases:

   - LOCKING UPSTREAMS: choose version of repositories to work from
   - PACKAGE GENERATION: work out what packages we want to include
   - SOLVING: work out versions of packages we want to include
   - FETCHING: download sources & apply any upstream patches
   - CUSTOM PATCHING: apply custom patches *)

let command = Command.group ~summary:"tools for working with vendored oxcaml packages" []
let run () = Command_unix.run command
