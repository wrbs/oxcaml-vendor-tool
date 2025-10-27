open! Core
open! Async
open Oxcaml_vendor_tool_lib

let update_patch_command =
  Command.async ~summary:"generates a patch file for a directory"
  @@
  let%map_open.Command project = Project.param
  and vendor_dir = anon ("VENDOR_DIR" %: Lock_file.Vendor_dir.arg_type)
  and modified_dir =
    flag
      "modified-dir"
      (optional string)
      ~doc:"(string) override modified dir (default: vendored output dir using config)"
  in
  fun () ->
    let%bind config = Configs.load (module Config) project
    and lock_file = Configs.load (module Lock_file) project in
    let patch_dir = Option.value_exn config.patches_dir in
    let dir_config = Map.find_exn lock_file vendor_dir in
    let cache_dir = Project.opam_download_cache project in
    let new_dir =
      match modified_dir with
      | Some d -> Filename_unix.realpath d
      | None ->
        Project.path project config.dest_dir ^/ Lock_file.Vendor_dir.to_string vendor_dir
    in
    let%bind () =
      match%map Sys.is_directory_exn new_dir with
      | false -> raise_s [%message "Not a directory" (new_dir : string)]
      | true -> ()
    in
    let temp_dir = Filename_unix.temp_dir "patch-gen" "dir" in
    let%bind () = Unix.symlink ~target:new_dir ~link_name:(temp_dir ^/ "b") in
    Fetch_upstreams.fetch_and_patch_dir
      ~dest_dir:(Opam.Par.return (temp_dir ^/ "a"))
      ~vendor_dir
      ~dir_config
      ~cache_dir
      ~no_patch:false
    |> Opam.Par.ignore
    |> Opam.Par.run_exn ~jobs:16;
    let%bind diff_output =
      Process.run_exn
        ~prog:"git"
        ~args:[ "diff"; "--no-index"; "--no-prefix"; "a/"; "b/" ]
        ~working_dir:temp_dir
        ~accept_nonzero_exit:[ 1 ]
        ()
    in
    let%bind () =
      match String.for_all diff_output ~f:Char.is_whitespace with
      | true ->
        print_endline "No diff detected";
        return ()
      | false ->
        let temp_patch_file = temp_dir ^/ "patch" in
        let%bind () = Writer.save temp_patch_file ~contents:diff_output in
        (match
           OpamSystem.patch ~allow_unclean:true ~dir:(temp_dir ^/ "a") temp_patch_file
         with
         | Some exn -> raise exn
         | None -> ());
        let%bind () =
          Process.run_expect_no_output_exn
            ~prog:"diff"
            ~args:[ "-ruN"; "a/"; "b/" ]
            ~working_dir:temp_dir
            ()
        in
        Core.print_string diff_output;
        (match OpamConsole.confirm "Save diff?" with
         | false -> return ()
         | true ->
           let%bind () = Unix.mkdir ~p:() patch_dir in
           Writer.save
             (patch_dir ^/ [%string "%{vendor_dir#Lock_file.Vendor_dir}.patch"])
             ~contents:diff_output)
    in
    Process.run_expect_no_output_exn ~prog:"rm" ~args:[ "-r"; temp_dir ] ()
;;
