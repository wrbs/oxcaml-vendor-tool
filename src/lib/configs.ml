open! Core
open! Async

let format_sexps sexps =
  let config = Sexp_pretty.Config.create ~color:false () ~new_line_separator:true in
  let buffer = Buffer.create 1024 in
  let formatter = Format.formatter_of_buffer buffer in
  let queue = Queue.of_list sexps in
  Sexp_pretty.pp_formatter' config formatter ~next:(fun () -> Queue.dequeue queue);
  Buffer.contents buffer
;;

module Make (M : sig
    type t [@@deriving sexp]

    val path : string
  end) =
struct
  let save t ~in_:project =
    let%bind () =
      match Filename.dirname M.path with
      | "." -> return ()
      | dir -> Unix.mkdir ~p:() (Project.path project dir)
    in
    let sexps =
      match [%sexp (t : M.t)] with
      | Atom _ -> failwith "list expected"
      | List sexps -> sexps
    in
    let contents = format_sexps sexps in
    Writer.save (Project.path project M.path) ~contents
  ;;

  let load project =
    let%map contents = Reader.file_contents (Project.path project M.path) in
    let sexps = Sexp.of_string_many contents in
    M.t_of_sexp (List sexps)
  ;;
end
