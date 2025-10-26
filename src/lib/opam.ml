open! Core
open! Async

module Identifiable_of_opam
    (T : sig
       type t [@@deriving string, compare]
     end)
    (Name : sig
       val module_name : string
     end) : Identifiable.S_not_binable with type t := T.t = struct
  module T' = struct
    include T
    include Name
    include Sexpable.Of_stringable (T)

    let hash t = [%hash: string] (to_string t)
    let hash_fold_t state t = [%hash_fold: string] state (to_string t)
  end

  include T'
  include Pretty_printer.Register (T')
  include Comparable.Make (T')
  include Hashable.Make (T')
end

module Package = struct
  module Name = struct
    type t = OpamPackage.Name.t

    include
      Identifiable_of_opam
        (OpamPackage.Name)
        (struct
          let module_name = "Opam.Package.Name"
        end)
  end

  module Version = struct
    type t = OpamPackage.Version.t

    include
      Identifiable_of_opam
        (OpamPackage.Version)
        (struct
          let module_name = "Opam.Package.Version"
        end)
  end

  module T = struct
    type t = OpamPackage.t [@@deriving string, compare]

    include
      Sexpable.Of_sexpable
        (struct
          type t = Name.t * Version.t [@@deriving sexp]
        end)
        (struct
          type nonrec t = t

          let to_sexpable (t : t) = t.name, t.version
          let of_sexpable (name, version) = OpamPackage.create name version
        end)

    let hash t = [%hash: string] (to_string t)
    let hash_fold_t state t = [%hash_fold: string] state (to_string t)
    let module_name = "Opam.Package"
  end

  include T
  include Pretty_printer.Register (T)
  include Comparable.Make (T)
  include Hashable.Make (T)
end

module Url = struct
  type t = OpamUrl.t [@@deriving string, compare]

  include Sexpable.Of_stringable (OpamUrl)
end

module Hash = struct
  type t = OpamHash.t [@@deriving string, compare]

  include Sexpable.Of_stringable (OpamHash)
end

module Relop = struct
  module Repr = struct
    module T = struct
      type t =
        | Eq [@rename "="]
        | Neq [@rename "<>"]
        | Geq [@rename ">="]
        | Gt [@rename ">"]
        | Leq [@rename "<="]
        | Lt [@rename "<"]
      [@@deriving string]
    end

    include T
    include Sexpable.Of_stringable (T)
  end

  type t = OpamFormula.relop [@@deriving compare]

  include
    Sexpable.Of_sexpable
      (Repr)
      (struct
        type nonrec t = t

        let to_sexpable : t -> Repr.t = function
          | `Eq -> Eq
          | `Neq -> Neq
          | `Geq -> Geq
          | `Gt -> Gt
          | `Leq -> Leq
          | `Lt -> Lt
        ;;

        let of_sexpable : Repr.t -> t = function
          | Eq -> `Eq
          | Neq -> `Neq
          | Geq -> `Geq
          | Gt -> `Gt
          | Leq -> `Leq
          | Lt -> `Lt
        ;;
      end)
end

module Version_formula = struct
  type base = Relop.t * Package.Version.t [@@deriving sexp]

  let neg_base (relop, version) = OpamFormula.neg_relop relop, version

  type t = OpamFormula.version_constraint OpamFormula.formula [@@deriving compare]

  let t_of_sexp sexp =
    let rec aux (sexp : Sexp.t) =
      let sexps =
        match sexp with
        | Atom _ -> of_sexp_error "expected list" sexp
        | List l -> l
      in
      match sexps with
      | Atom "and" :: (_ :: _ as children) ->
        let ands = List.map children ~f:aux in
        OpamFormula.ands ands
      | Atom "or" :: (_ :: _ as children) ->
        let ors = List.map children ~f:aux in
        OpamFormula.ors ors
      | [ Atom "not"; child ] ->
        let t' = aux child in
        OpamFormula.neg neg_base t'
      | _ -> OpamFormula.Atom (base_of_sexp sexp)
    in
    match (sexp : Sexp.t) with
    | List [] -> OpamFormula.Empty
    | _ -> aux sexp
  ;;

  let rec sexp_of_t t =
    match (t : t) with
    | Empty -> [%sexp []]
    | Atom base -> [%sexp (base : base)]
    | And _ ->
      let children = List.map (OpamFormula.ands_to_list t) ~f:sexp_of_t in
      [%sexp "and" :: (children : Sexp.t list)]
    | Or _ ->
      let children = List.map (OpamFormula.ors_to_list t) ~f:sexp_of_t in
      [%sexp "and" :: (children : Sexp.t list)]
    | Block t -> sexp_of_t t
  ;;

  let exact version : t = Atom (`Eq, version)
end

module Opam_file = struct
  module Url = struct
    type t = OpamFile.URL.t

    let sexp_of_t t =
      let url = OpamFile.URL.url t in
      let mirrors = OpamFile.URL.mirrors t in
      let checksum = OpamFile.URL.checksum t in
      let subpath =
        OpamFile.URL.subpath t |> Option.map ~f:OpamFilename.SubPath.to_string
      in
      [%sexp
        (url : Url.t)
        :: { mirrors : (Url.t list[@sexp.list])
           ; checksum : (Hash.t list[@sexp.list])
           ; subpath : (string option[@sexp.option])
           }]
    ;;
  end

  type t = OpamFile.OPAM.t
  type relop = OpamParserTypes.FullPos.relop
  type logop = OpamParserTypes.FullPos.logop
  type pfxop = OpamParserTypes.FullPos.pfxop
  type env_update_op = OpamParserTypes.FullPos.env_update_op

  let sexp_string to_string x = [%sexp (to_string x : string)]
  let sexp_of_relop : [%sexp_of: relop] = sexp_string OpamPrinter.FullPos.relop
  let sexp_of_logop : [%sexp_of: logop] = sexp_string OpamPrinter.FullPos.logop
  let sexp_of_pfxop : [%sexp_of: pfxop] = sexp_string OpamPrinter.FullPos.pfxop

  let sexp_of_env_update_op : [%sexp_of: env_update_op] =
    sexp_string OpamPrinter.FullPos.env_update_op
  ;;

  type value = OpamParserTypes.FullPos.value

  let rec sexp_of_value (value : value) =
    match value.pelem with
    | Bool b -> [%sexp (b : bool)]
    | Int i -> [%sexp (i : int)]
    | String s -> [%sexp (s : string)]
    | Relop (op, v, v') -> [%sexp [ (op : relop); (v : value); (v' : value) ]]
    | Prefix_relop (op, v) -> [%sexp [ (op : relop); (v : value) ]]
    | Logop (op, v, v') -> [%sexp [ (op : logop); (v : value); (v' : value) ]]
    | Pfxop (op, v) -> [%sexp [ (op : pfxop); (v : value) ]]
    | Ident s -> [%sexp ([%string "<%{s}>"] : string)]
    | List { pelem = vs; _ } -> [%sexp (vs : value list)]
    | Group { pelem = vs; _ } -> [%sexp (vs : value list)]
    | Option (v, { pelem = vs; _ }) -> [%sexp [ (v : value); (vs : value list) ]]
    | Env_binding (v, op, v') ->
      [%sexp [ (v : value); (op : env_update_op); (v' : value) ]]
  ;;

  type opamfile_item = OpamParserTypes.FullPos.opamfile_item

  let rec sexp_of_opamfile_item (item : opamfile_item) =
    match item.pelem with
    | Section
        { section_kind = { pelem = kind; _ }
        ; section_name = None
        ; section_items = { pelem = items; _ }
        } -> [%sexp (kind : string) :: (items : opamfile_item list)]
    | Section
        { section_kind = { pelem = kind; _ }
        ; section_name = Some { pelem = name; _ }
        ; section_items = { pelem = items; _ }
        } -> [%sexp (kind : string) :: (name : string) :: (items : opamfile_item list)]
    | Variable ({ pelem = name; _ }, value) ->
      [%sexp [ (name : string); (value : value) ]]
  ;;

  let sexp_of_t t =
    let items = (OpamFile.OPAM.contents t).file_contents in
    [%sexp (items : opamfile_item list)]
  ;;
end

module Filter = struct
  type t = OpamTypes.filter

  let compare = Comparable.lift [%compare: string] ~f:OpamFilter.to_string

  let var_to_string packages var =
    let var = OpamVariable.to_string var in
    match packages with
    | [] -> var
    | _ ->
      let prefix =
        List.map packages ~f:(Option.value_map ~f:Package.Name.to_string ~default:"_")
        |> String.concat ~sep:"+"
      in
      [%string "%{prefix}:%{var}"]
  ;;

  let var_of_string s =
    match String.lsplit2 s ~on:':' with
    | None -> [], OpamVariable.of_string s
    | Some (package_string, v) ->
      let packages =
        String.split package_string ~on:'+'
        |> List.map ~f:(function
          | "_" -> None
          | pkg -> Some (OpamPackage.Name.of_string pkg))
      in
      packages, OpamVariable.of_string v
  ;;

  let rec sexp_of_t (t : t) =
    match t with
    | FBool true -> [%sexp "true"]
    | FBool false -> [%sexp "false"]
    | FString s -> [%sexp (s : string)]
    | FIdent (packages, var, None) -> [%sexp [ (var_to_string packages var : string) ]]
    | FIdent (packages, var, Some (if_true, if_false)) ->
      [%sexp
        [ "%?"
        ; (var_to_string packages var : string)
        ; (if_true : string)
        ; (if_false : string)
        ]]
    | FOp (t1, op, t2) -> [%sexp [ (op : Relop.t); (t1 : t); (t2 : t) ]]
    | FAnd (t1, t2) -> [%sexp [ "&"; (t1 : t); (t2 : t) ]]
    | FOr (t1, t2) -> [%sexp [ "|"; (t1 : t); (t2 : t) ]]
    | FNot t -> [%sexp [ "!"; (t : t) ]]
    | FDefined t -> [%sexp [ "?"; (t : t) ]]
    | FUndef t -> [%sexp [ "!undef"; (t : t) ]]
  ;;

  let rec t_of_sexp : Sexp.t -> t = function
    | Atom "true" -> FBool true
    | Atom "false" -> FBool false
    | Atom s -> FString s
    | List [ s ] ->
      let packages, var = var_of_string ([%of_sexp: string] s) in
      FIdent (packages, var, None)
    | List [ Atom "%?"; s; if_true; if_false ] ->
      let packages, var = var_of_string ([%of_sexp: string] s) in
      let if_true = [%of_sexp: string] if_true in
      let if_false = [%of_sexp: string] if_false in
      FIdent (packages, var, Some (if_true, if_false))
    | List [ Atom op; s1; s2 ] ->
      let t1 = [%of_sexp: t] s1 in
      let t2 = [%of_sexp: t] s2 in
      (match op with
       | "&" -> FAnd (t1, t2)
       | "|" -> FOr (t1, t2)
       | _ ->
         let relop = [%of_sexp: Relop.t] (Atom op) in
         FOp (t1, relop, t2))
    | List [ (Atom op as atom); s ] ->
      let t = [%of_sexp: t] s in
      (match op with
       | "!" -> FNot t
       | "?" -> FDefined t
       | "!undef" -> FUndef t
       | _ -> of_sexp_error "invalid filter" atom)
    | sexp -> of_sexp_error "invalid filter" sexp
  ;;
end

module Filtered = struct
  type 'a t = 'a * Filter.t option [@@deriving compare]

  let sexp_of_t sexp_of_a (a, filter) =
    match filter with
    | None -> sexp_of_a a
    | Some filter -> [%sexp [ (a : a); ":if"; (filter : Filter.t) ]]
  ;;

  let t_of_sexp a_of_sexp sexp =
    match (sexp : Sexp.t) with
    | List [ a; Atom ":if"; b ] -> a_of_sexp a, Some ([%of_sexp: Filter.t] b)
    | _ -> a_of_sexp sexp, None
  ;;
end

module Job = struct
  type 'a t = 'a OpamProcess.job

  include Monad.Make (struct
      type nonrec 'a t = 'a t

      let return x : _ t = Done x
      let bind = fun t ~f -> OpamProcess.Job.Op.(t @@+ f)
      let map = `Custom (fun t ~f -> OpamProcess.Job.Op.(t @@| f))
    end)

  let run : 'a t -> 'a = OpamProcess.Job.run
  let command command = OpamProcess.Job.Op.(command @@> return)
end

module Par = struct
  module Vertex_id = struct
    include Unique_id.Int ()
  end

  module Vertex = struct
    type t =
      { num : int
      ; desc : string option
      }
    [@@deriving sexp, compare, hash, equal]

    include Hashable.Make (struct
        type nonrec t = t [@@deriving sexp, compare, hash]
      end)

    let to_string t =
      match t.desc with
      | None -> Int.to_string t.num
      | Some desc -> [%string "%{desc} [%{t.num#Int}]"]
    ;;

    let of_string s =
      match String.rsplit2 s ~on:'[' with
      | None -> { num = Int.of_string s; desc = None }
      | Some (desc, rest) ->
        { num = Int.of_string (String.drop_suffix rest 1); desc = Some desc }
    ;;

    let to_json t = `String (to_string t)

    let of_json = function
      | `String s -> Some (of_string s)
      | _ -> None
    ;;
  end

  module G = OpamParallel.MakeGraph (Vertex)

  module Key = struct
    type 'a t =
      { id : Vertex_id.t
      ; desc : string option
      ; univ_key : 'a Type_equal.Id.t [@sexp.opaque]
      }

    and getter = { get : 'a. 'a t -> 'a }

    let create desc =
      let id = Vertex_id.create () in
      let univ_key =
        Type_equal.Id.create
          ~name:(Vertex.to_string { num = (id :> int); desc })
          [%sexp_of: _]
      in
      { id; desc; univ_key }
    ;;
  end

  module Of_deps = struct end

  module Node = struct
    type 'a t =
      { key : 'a Key.t
      ; deps : packed list
      ; f : Key.getter -> 'a Job.t
      }

    and packed = T : _ t -> packed

    let create deps f ~desc =
      let key = Key.create desc in
      { key; deps; f }
    ;;
  end

  type _ t =
    | Const : 'a -> 'a t
    | Getter :
        { deps : Node.packed list
        ; f : Key.getter -> 'a
        }
        -> 'a t

  let return x = Const x

  let get = function
    | Const x -> [], fun _ -> x
    | Getter { deps; f } -> deps, f
  ;;

  let spawn ?desc x ~f =
    let deps, get_arg = get x in
    let node = Node.create deps (fun getter -> f (get_arg getter)) ~desc in
    Getter { f = (fun getter -> getter.get node.key); deps = T node :: deps }
  ;;

  let job ?desc (job : _ Job.t) =
    match job with
    | Done x -> Const x
    | _ -> spawn ?desc (Const ()) ~f:(fun () -> job)
  ;;

  let map ?desc x ~f =
    match x with
    | Const v -> Const (f v)
    | Getter _ -> spawn ?desc x ~f:(fun v -> Job.return (f v))
  ;;

  let uncached_map x ~f:map_f =
    match x with
    | Const v -> Const (map_f v)
    | Getter { deps; f } -> Getter { deps; f = (fun g -> map_f (f g)) }
  ;;

  let ignore t =
    let deps, _ = get t in
    match deps with
    | [] -> return ()
    | _ -> Getter { deps; f = (fun _ -> ()) }
  ;;

  let both ta tb =
    match ta, tb with
    | Const xa, Const xb -> Const (xa, xb)
    | Const xa, Getter { deps; f } -> Getter { deps; f = (fun map -> xa, f map) }
    | Getter { deps; f }, Const xb -> Getter { deps; f = (fun map -> f map, xb) }
    | Getter { deps = deps_a; f = f_a }, Getter { deps = deps_b; f = f_b } ->
      Getter { deps = deps_a @ deps_b; f = (fun map -> f_a map, f_b map) }
  ;;

  let all ts =
    let deps, getters = List.map ts ~f:get |> List.unzip in
    Getter
      { deps = List.concat deps
      ; f = (fun getter -> List.map getters ~f:(fun g -> g getter))
      }
  ;;

  let all_unit ts =
    let deps =
      List.concat_map ts ~f:(fun t ->
        let deps, _ = get t in
        deps)
    in
    Getter { deps; f = (fun _ -> ()) }
  ;;

  module Failure = struct
    type extra =
      [ `msg of string
      | `raw of string
      ]

    type t =
      { message : string
      ; extra : extra option
      }

    let createf ?extra cont fmt =
      let extra =
        let error error = `raw (Error.to_string_hum error ^ "\n") in
        Option.map extra ~f:(function
          | `error e -> error e
          | `exn exn -> `raw (Stdlib.Printexc.to_string exn ^ "\n")
          | `exn_backtrace exn ->
            let backtrace = Backtrace.get () in
            `raw [%string "%{Stdlib.Printexc.to_string exn}\n%{backtrace#Backtrace}\n"]
          | `raw s -> `raw s
          | `msg s -> `msg s)
      in
      Printf.ksprintf (fun message -> cont { message; extra }) fmt
    ;;
  end

  exception Failed of Failure.t
  exception Skipped

  let fail ?extra fmt = Failure.createf ?extra (fun failure -> raise (Failed failure)) fmt

  let fail_details fmt =
    Printf.ksprintf
      (fun message fmt ->
         Printf.ksprintf (fun details -> fail ~extra:(`msg details) "%s" message) fmt)
      fmt
  ;;

  type 'a command_output =
    | Expect_none : unit command_output
    | Ignore : unit command_output
    | Return : string list command_output

  let command_or_fail (type a) command ~(output : a command_output) =
    let%map.Job result = Job.command command in
    let name = Option.value command.cmd_name ~default:command.cmd in
    let stdout =
      match result.r_code with
      | 0 -> result.r_stdout
      | code ->
        fail
          "command %s failed with code %d"
          name
          code
          ~extra:(`raw (OpamProcess.string_of_result result))
    in
    match output with
    | Return -> (stdout : a)
    | Ignore -> ()
    | Expect_none ->
      if List.is_empty stdout
      then ()
      else
        fail
          "command %s returned unexpected output"
          name
          ~extra:(`raw (OpamProcess.string_of_result result))
  ;;

  module Compiled = struct
    type 'a t =
      { nodes : Node.packed Vertex.Table.t
      ; graph : G.t
      ; get_root : Key.getter -> 'a
      }

    let output_dot t channel = G.Dot.output_graph channel t.graph
    let json t = G.to_json t.graph |> OpamJson.to_string

    let report_and_reraise (failure : Failure.t) ~desc =
      let failure =
        match desc with
        | None -> failure
        | Some desc -> { failure with message = [%string "[%{desc}] %{failure.message}"] }
      in
      OpamConsole.error "%s" failure.message;
      raise (Failed failure)
    ;;

    let wrap_failures f ~desc =
      try f () with
      | Skipped -> raise Skipped
      | Failed failure -> report_and_reraise failure ~desc
      | exn ->
        Failure.createf
          (fun failure -> report_and_reraise failure ~desc)
          ~extra:(`exn_backtrace exn)
          "exception raised"
    ;;

    let report_long exns =
      let failures =
        List.filter_map exns ~f:(function
          | _, Failed failure -> Some failure
          | _ -> None)
      in
      OpamConsole.header_error "Failures while running jobs" "";
      List.iter failures ~f:(fun failure ->
        OpamConsole.error "%s" failure.message;
        Option.iter failure.extra ~f:(function
          | `msg msg -> OpamConsole.formatted_errmsg "%s" msg
          | `raw msg -> OpamConsole.errmsg "%s" msg));
      ()
    ;;

    let run t ~jobs =
      let results = Vertex_id.Table.create () in
      let getter =
        { Key.get =
            (fun key ->
              match Hashtbl.find results key.id with
              | Some univ -> Univ.match_exn univ key.univ_key
              | None -> raise Skipped)
        }
      in
      match
        G.Parallel.iter t.graph ~jobs ~command:(fun ~pred:_ vertex ->
          wrap_failures ~desc:vertex.desc (fun () ->
            let (T node) = Hashtbl.find_exn t.nodes vertex in
            let job = node.f getter in
            let%map.Job result = job in
            Hashtbl.add_exn
              results
              ~key:node.key.id
              ~data:(Univ.create node.key.univ_key result)))
      with
      | () -> Ok (t.get_root getter)
      | exception G.Parallel.Errors (_, exns, _) ->
        report_long exns;
        Error ()
    ;;

    let run_exn t ~jobs =
      match run t ~jobs with
      | Error () -> failwith "jobs failed"
      | Ok x -> x
    ;;
  end

  let compile t =
    let count = ref 0 in
    let vertices = Vertex_id.Table.create () in
    let nodes = Vertex.Table.create () in
    let graph = G.create () in
    let rec aux packed =
      let (Node.T node) = packed in
      match Hashtbl.find vertices node.key.id with
      | Some vertex -> vertex
      | None ->
        let num = !count in
        count := num + 1;
        let vertex = { Vertex.num; desc = node.key.desc } in
        G.add_vertex graph vertex;
        Hashtbl.add_exn vertices ~key:node.key.id ~data:vertex;
        Hashtbl.add_exn nodes ~key:vertex ~data:packed;
        List.iter node.deps ~f:(fun dep ->
          let parent = aux dep in
          G.add_edge graph parent vertex);
        vertex
    in
    let deps, get_root = get t in
    List.iter deps ~f:(fun dep ->
      let _ = (aux dep : Vertex.t) in
      ());
    { Compiled.nodes; graph; get_root }
  ;;

  let run t ~jobs = compile t |> Compiled.run ~jobs
  let run_exn t ~jobs = compile t |> Compiled.run_exn ~jobs

  module Let_syntax = struct
    module Let_syntax = struct
      let map x ~f = map x ~f
      let bind x ~f = spawn x ~f
      let both = both
    end
  end

  module Desc = struct
    module Let_syntax = struct
      module Let_syntax = struct
        let map (desc, x) ~f = map x ~f ~desc
        let bind (desc, x) ~f = spawn x ~f ~desc
        let both a (desc, b) = desc, both a b
      end
    end
  end
end
