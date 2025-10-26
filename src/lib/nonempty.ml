open! Core

type 'a t = ( :: ) of 'a * 'a list [@@deriving compare, equal]

let to_list (x :: xs) : _ list = x :: xs

let of_list (l : _ list) =
  match l with
  | [] -> None
  | x :: xs -> Some (x :: xs)
;;

let of_list_exn l =
  of_list l
  |> Option.value_or_thunk ~default:(fun () -> failwith "expected nonempty list")
;;

let sexp_of_t sexp_of_a t = List.sexp_of_t sexp_of_a (to_list t)

let t_of_sexp a_of_sexp sexp =
  match List.t_of_sexp a_of_sexp sexp with
  | [] -> of_sexp_error "expected nonempty list" sexp
  | x :: xs -> x :: xs
;;
