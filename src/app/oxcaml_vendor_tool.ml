open! Core
open! Async

let command =
  Command.group
    ~summary:"tools for working with vendored oxcaml packages"
    [ "lock", Oxcaml_vendor_tool_solver.lock_command
    ; "lock-phases", Oxcaml_vendor_tool_solver.phases_command
    ; "fetch", Oxcaml_vendor_tool_fetch_and_patch.fetch_command
    ]
;;

let run () = Command_unix.run command
