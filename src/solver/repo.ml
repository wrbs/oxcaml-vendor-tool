open! Core
open Oxcaml_vendor_tool_lib

let repos_dir project = Project.path project (Project.cache_dir ^/ "repos")

include
  String_id.Make
    (struct
      let module_name = "Repo"
    end)
    ()

let dir t ~project = repos_dir project ^/ to_string t
let opam_dir t ~project = dir t ~project |> OpamFilename.Dir.of_string
