open! Core
open! Async
open Oxcaml_vendor_tool_lib

let handle_download_result job =
  match%map.Opam.Job job with
  | OpamTypes.Up_to_date _ | Result _ -> Ok ()
  | Not_available (_, details) -> Or_error.error_string details
;;

let iter_job_or_error l ~f =
  List.fold l ~init:(Opam.Job.Or_error.return ()) ~f:(fun prev x ->
    let%bind.Opam.Job.Or_error () = prev in
    f x)
;;

let fetch_and_patch_dir
      ~root
      ~dir
      ~(dir_config : Lock_file.Vendor_dir_config.t)
      ~cache_dir
      ~no_patch
  =
  let desc = Lock_file.Vendor_dir.to_string dir in
  let dest_dir = root ^/ Lock_file.Vendor_dir.to_string dir in
  let url, hash =
    match dir_config.source with
    | Http { url; hash } -> [ OpamUrl.of_string url ], [ Lock_file.Hash.to_opam hash ]
    | Git { url; rev } ->
      [ { (OpamUrl.of_string url) with backend = `git; hash = Some rev } ], []
  in
  let fetch_dir =
    Opam.Par.job
      ~desc
      (OpamRepository.pull_tree
         desc
         (OpamFilename.Dir.of_string dest_dir)
         hash
         url
         ~cache_dir
       |> handle_download_result)
  in
  let fetch_extra =
    Opam.Par.all
      (Map.to_alist dir_config.extra
       |> List.map ~f:(fun (filename, { url; hash }) ->
         let desc = [%string "%{desc}:%{filename}"] in
         Opam.Par.spawn ~desc fetch_dir ~f:(function
           | Error _ -> Opam.Job.return None
           | Ok () ->
             OpamRepository.pull_file
               desc
               (OpamFilename.of_string (dest_dir ^/ filename))
               [ Lock_file.Hash.to_opam hash ]
               [ OpamUrl.of_string url ]
               ~cache_dir
             |> handle_download_result
             |> Opam.Job.map ~f:Option.some)))
    |> Opam.Par.map ~desc:(desc ^ ":all-unit") ~f:(fun results ->
      List.filter_opt results |> Or_error.all_unit)
  in
  let%bind.Opam.Par.Desc a = fetch_dir
  and b = desc ^ ":bind", fetch_extra in
  let%bind.Opam.Job.Or_error () = Opam.Job.return (Or_error.all_unit [ a; b ]) in
  let%bind.Opam.Job.Or_error () =
    iter_job_or_error dir_config.patches ~f:(fun patch ->
      Opam.Job.return
      @@
      if no_patch
      then Ok ()
      else (
        match OpamSystem.patch ~allow_unclean:true ~dir:dest_dir (dest_dir ^/ patch) with
        | None -> Ok ()
        | Some exn ->
          Or_error.error_s [%message "Error patching" (patch : string) (exn : exn)]))
  in
  iter_job_or_error dir_config.prepare_commands ~f:(function
    | [] -> Opam.Job.Or_error.return ()
    | command :: args ->
      Opam.Job.Or_error.command
        (OpamProcess.command ~dir:dest_dir ~text:command command args))
;;

let fetch_command =
  Command.async
    ~summary:"fetch all sources, apply upstream patches and run prepare commands"
  @@
  let%map_open.Command project = Project.param
  and jobs =
    flag_optional_with_default_doc
      "jobs"
      int
      [%sexp_of: int]
      ~default:16
      ~doc:"(int) number of opam jobs to run"
  and no_patch = flag "no-patch" no_arg ~doc:"don't patch" in
  fun () ->
    let%bind dirs = Configs.load (module Lock_file) project in
    let cache_dir = Project.path project "_cache/opam" |> OpamFilename.Dir.of_string in
    let tmp_dir = Project.path project "_cache/tmp" in
    let%bind () =
      Process.run_expect_no_output_exn ~prog:"rm" ~args:[ "-rf"; tmp_dir ] ()
    in
    let%bind () = Unix.mkdir ~p:() tmp_dir in
    let graph =
      Map.to_alist dirs
      |> List.map ~f:(fun (dir, dir_config) ->
        fetch_and_patch_dir ~root:tmp_dir ~dir ~dir_config ~cache_dir ~no_patch)
      |> Opam.Par.all
      |> Opam.Par.compile
    in
    graph |> Opam.Par.Compiled.run ~jobs |> Or_error.all_unit |> Or_error.ok_exn;
    return ()
;;
