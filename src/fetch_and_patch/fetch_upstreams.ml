open! Core
open! Async
open Oxcaml_vendor_tool_lib

let handle_download_result job =
  match%map.Opam.Job job with
  | OpamTypes.Up_to_date _ | Result _ -> ()
  | Not_available (_, details) -> Opam.Par.fail_details "error fetching" "%s" details
;;

let make_desc s ~vendor_dir = [%string "%{vendor_dir#Lock_file.Vendor_dir}:%{s}"]

let fetch_sources
      ~dest_dir
      ~vendor_dir
      ~(dir_config : Lock_file.Vendor_dir_config.t)
      ~cache_dir
  =
  let fetch_main =
    let desc = make_desc "fetch-main-source" ~vendor_dir in
    Opam.Par.spawn ~desc dest_dir ~f:(fun dest_dir ->
      let%map.Opam.Job () =
        OpamRepository.pull_tree
          desc
          (OpamFilename.Dir.of_string dest_dir)
          (Lock_file.Main_source.opam_hashes dir_config.source)
          (Lock_file.Main_source.opam_urls dir_config.source)
          ~cache_dir
          ~full_fetch:false
        |> handle_download_result
      in
      `Main_source dest_dir)
  in
  let fetch_extra =
    Map.to_alist dir_config.extra
    |> List.map ~f:(fun (filename, source) ->
      let desc = make_desc [%string "fetch-extra:%{filename}"] ~vendor_dir in
      Opam.Par.spawn ~desc fetch_main ~f:(fun (`Main_source dest_dir) ->
        OpamRepository.pull_file
          desc
          (OpamFilename.of_string (dest_dir ^/ filename))
          (Lock_file.Http_source.opam_hashes source)
          (Lock_file.Http_source.opam_urls source)
          ~cache_dir
          ~silent_hits:true
        |> handle_download_result))
    |> Opam.Par.all_unit
  in
  let%map.Opam.Par (`Main_source dest_dir) = fetch_main
  and () = fetch_extra in
  `All_sources dest_dir
;;

let apply_patches
      ~dir_with_sources
      ~vendor_dir
      ~(dir_config : Lock_file.Vendor_dir_config.t)
  =
  let patched_sources =
    if List.is_empty dir_config.patches
    then
      Opam.Par.uncached_map dir_with_sources ~f:(fun (`All_sources dir) ->
        `Sources_patched dir)
    else (
      let desc = make_desc "patches" ~vendor_dir in
      let%map.Opam.Par.Desc (`All_sources dest_dir) = desc, dir_with_sources in
      List.iter dir_config.patches ~f:(fun patch ->
        let patch_file = dest_dir ^/ patch in
        match OpamSystem.patch ~allow_unclean:true ~dir:dest_dir patch_file with
        | None -> OpamSystem.remove_file patch_file
        | Some exn -> Opam.Par.fail ~extra:(`exn exn) "error applying patch %s" patch);
      `Sources_patched dest_dir)
  in
  List.foldi dir_config.prepare_commands ~init:patched_sources ~f:(fun idx cur -> function
    | [] -> cur
    | command :: args ->
      let desc = make_desc [%string "prepare-cmd:%{idx#Int}"] ~vendor_dir in
      let%bind.Opam.Par.Desc (`Sources_patched dest_dir) = desc, cur in
      let%map.Opam.Job () =
        Opam.Par.command_or_fail
          (OpamProcess.command ~dir:dest_dir ~name:desc command args)
          ~output:Ignore
      in
      `Sources_patched dest_dir)
;;

let fetch_and_patch_dir ~dest_dir ~vendor_dir ~dir_config ~cache_dir ~no_patch =
  let fetched_sources = fetch_sources ~dest_dir ~vendor_dir ~dir_config ~cache_dir in
  let patched_sources =
    if no_patch
    then
      Opam.Par.uncached_map fetched_sources ~f:(fun (`All_sources dir) ->
        `Sources_patched dir)
    else apply_patches ~dir_with_sources:fetched_sources ~vendor_dir ~dir_config
  in
  Opam.Par.spawn
    patched_sources
    ~desc:(make_desc "done" ~vendor_dir)
    ~f:(fun (`Sources_patched dest_dir) ->
      OpamConsole.msg
        "[%s] fetched\n"
        (OpamConsole.colorise `green (Lock_file.Vendor_dir.to_string vendor_dir));
      Opam.Job.return dest_dir)
;;

let execute ~dest ~jobs ~dirs ~project ~no_patch =
  let cache_dir = Project.opam_download_cache project in
  let%bind () = Process.run_expect_no_output_exn ~prog:"rm" ~args:[ "-rf"; dest ] () in
  let%map () = Unix.mkdir ~p:() dest in
  let dest = Filename_unix.realpath dest in
  Map.to_alist dirs
  |> List.map ~f:(fun (vendor_dir, dir_config) ->
    let dest_dir = dest ^/ Lock_file.Vendor_dir.to_string vendor_dir in
    fetch_and_patch_dir
      ~dest_dir:(Opam.Par.return dest_dir)
      ~vendor_dir
      ~dir_config
      ~cache_dir
      ~no_patch
    |> Opam.Par.ignore)
  |> Opam.Par.all_unit
  |> Opam.Par.run ~jobs
;;

let command =
  Command.async
    ~summary:"fetch all sources and apply upstream patches, writing result to \n    "
  @@
  let%map_open.Command project = Project.param
  and dest_dir = anon ("DEST_DIR" %: string)
  and jobs = Opam.jobs_flag
  and no_patch = flag "no-patch" no_arg ~doc:"don't patch" in
  fun () ->
    let%bind dirs = Configs.load (module Lock_file) project in
    match%bind execute ~dest:dest_dir ~dirs ~project ~jobs ~no_patch with
    | Ok () -> return ()
    | Error () -> exit 1
;;
