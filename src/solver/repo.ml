open! Core
open Oxcaml_vendor_tool_lib

let repos_dir project = Project.path project "_cache/repos"

include
  String_id.Make
    (struct
      let module_name = "Repo"
    end)
    ()

let to_opam t = OpamRepositoryName.of_string (to_string t)
let dir t ~project = repos_dir project ^/ to_string t
let opam_dir t ~project = dir t ~project |> OpamFilename.Dir.of_string
