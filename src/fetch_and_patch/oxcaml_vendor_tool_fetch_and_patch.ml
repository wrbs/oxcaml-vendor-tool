open! Core
open! Async

let commands =
  [ "fetch-upstreams", Fetch_upstreams.command
  ; "pull", Pull.pull_command
  ; "pull-single", Pull.pull_single_command
  ; "update-patch", Patch_manager.update_patch_command
  ]
;;
