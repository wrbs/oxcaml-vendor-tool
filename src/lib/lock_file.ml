open! Core

module Vendor_dir = struct
  include
    String_id.Make
      (struct
        let module_name = "Vendor_dir"
      end)
      ()
end

module Http_url = struct
  type t = string [@@deriving sexp]

  let of_string_opt s =
    let%bind.Option uri = Option.try_with (fun () -> Uri.of_string s) in
    match Uri.scheme uri with
    | Some ("http" | "https") -> Some s
    | _ -> None
  ;;

  let to_opam t = OpamUrl.of_string t

  let merge a b =
    let a' = Nonempty.to_list a in
    let b' =
      Nonempty.to_list b
      |> List.filter ~f:(fun url -> not (List.mem a' url ~equal:[%equal: string]))
    in
    a' @ b' |> Nonempty.of_list_exn
  ;;
end

module Http_source = struct
  type t =
    { urls : Http_url.t Nonempty.t
    ; hashes : Opam.Hash.t Nonempty.t
    }
  [@@deriving sexp]

  let of_opam_file file_url =
    let%map.Option urls =
      OpamFile.URL.url file_url :: OpamFile.URL.mirrors file_url
      |> List.filter_map ~f:(fun url ->
        match url.backend with
        | `http -> Http_url.of_string_opt (OpamUrl.base_url url)
        | _ -> None)
      |> Nonempty.of_list
    and hashes = Nonempty.of_list (OpamFile.URL.checksum file_url)
    and () = Option.some_if (Option.is_none (OpamFile.URL.subpath file_url)) () in
    { urls; hashes }
  ;;

  let merge_hashes a b =
    Nonempty.to_list a @ Nonempty.to_list b
    |> List.sort_and_group
         ~compare:(Comparable.lift OpamHash.compare_kind ~f:OpamHash.kind)
    |> List.map ~f:(fun same_kind_hashes ->
      match List.dedup_and_sort same_kind_hashes ~compare:OpamHash.compare with
      | [ hash ] -> Some hash
      | _ -> None)
    |> Option.all
    |> Option.map ~f:Nonempty.of_list_exn
  ;;

  let merge_opt t t' =
    let%map.Option hashes = merge_hashes t.hashes t'.hashes in
    let urls = Http_url.merge t.urls t'.urls in
    { urls; hashes }
  ;;

  let opam_urls t = Nonempty.to_list t.urls |> List.map ~f:Http_url.to_opam
  let opam_hashes t = Nonempty.to_list t.hashes
end

let reduce_opt l ~f =
  let exception No_merge in
  try
    List.reduce l ~f:(fun x x' ->
      match f x x' with
      | Some x'' -> x''
      | None -> raise No_merge)
  with
  | No_merge -> None
;;

module Git_source = struct
  type t =
    { urls : Http_url.t Nonempty.t
    ; commit : string
    }
  [@@deriving sexp]

  let merge_opt t t' =
    if [%equal: string] t.commit t'.commit
    then Some { urls = Http_url.merge t.urls t'.urls; commit = t.commit }
    else None
  ;;

  let opam_urls t =
    Nonempty.to_list t.urls
    |> List.map ~f:Http_url.to_opam
    |> List.map ~f:(fun url -> { url with backend = `git; hash = Some t.commit })
  ;;

  let is_commit_hash s =
    let length = String.length s in
    String.for_all s ~f:Char.is_hex_digit_lower && (length = 40 || length = 64)
  ;;

  let of_opam_file file_url =
    let%bind.Option t =
      OpamFile.URL.url file_url :: OpamFile.URL.mirrors file_url
      |> List.filter_map ~f:(fun url ->
        match url.backend with
        | `git ->
          let%map.Option commit = url.hash
          and http_url =
            Http_url.of_string_opt
              (OpamUrl.to_string { url with hash = None; backend = `http })
          in
          { urls = [ http_url ]; commit }
        | _ -> None)
      |> reduce_opt ~f:merge_opt
    in
    Option.some_if (is_commit_hash t.commit) t
  ;;
end

module Main_source = struct
  module Base = struct
    type t =
      | Http of Http_source.t
      | Git of Git_source.t
    [@@deriving sexp]

    let merge_opt t t' =
      match t, t' with
      | Http a, Http b ->
        let%map.Option x = Http_source.merge_opt a b in
        Http x
      | Git a, Git b ->
        let%map.Option x = Git_source.merge_opt a b in
        Git x
      | _ -> None
    ;;

    let of_url_without_subpath file_url =
      match Http_source.of_opam_file file_url with
      | Some http -> Some (Http http)
      | None ->
        let%map.Option git = Git_source.of_opam_file file_url in
        Git git
    ;;
  end

  type t =
    { base : Base.t
    ; subpath : string option
    }
  [@@deriving sexp]

  let of_opam_file file_url =
    let%map.Option base =
      Base.of_url_without_subpath (OpamFile.URL.with_subpath_opt None file_url)
    in
    let subpath =
      OpamFile.URL.subpath file_url |> Option.map ~f:OpamFilename.SubPath.to_string
    in
    { base; subpath }
  ;;

  let merge_opt t t' =
    let%map.Option subpath =
      Option.some_if ([%equal: string option] t.subpath t'.subpath) t.subpath
    and base = Base.merge_opt t.base t'.base in
    { base; subpath }
  ;;

  let opam_urls t =
    match t.base with
    | Http x -> Http_source.opam_urls x
    | Git x -> Git_source.opam_urls x
  ;;

  let opam_hashes t =
    match t.base with
    | Http x -> Http_source.opam_hashes x
    | Git _ -> []
  ;;
end

module Vendor_dir_config = struct
  type t =
    { source : Main_source.t
    ; extra : Http_source.t String.Map.t
          [@default String.Map.empty] [@sexp_drop_if Map.is_empty]
    ; patches : string list [@sexp.list]
    ; prepare_commands : string list list [@sexp.list]
    }
  [@@deriving sexp]
end

let path = "lock.sexp"

type t = Vendor_dir_config.t Vendor_dir.Map.t [@@deriving sexp]
