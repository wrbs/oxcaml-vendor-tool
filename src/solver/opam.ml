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

module Version_formula = struct
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

module Job = struct
  type 'a t = 'a OpamProcess.job

  include Monad.Make (struct
      type nonrec 'a t = 'a t

      let return x : _ t = Done x
      let bind = fun t ~f -> OpamProcess.Job.Op.(t @@+ f)
      let map = `Custom (fun t ~f -> OpamProcess.Job.Op.(t @@| f))
    end)

  let run : 'a t -> 'a = OpamProcess.Job.run
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

  module Compiled = struct
    type 'a t =
      { nodes : Node.packed Vertex.Table.t
      ; graph : G.t
      ; get_root : Key.getter -> 'a
      }

    let output_dot t channel = G.Dot.output_graph channel t.graph

    let run t ~jobs =
      let results = Vertex_id.Table.create () in
      let getter =
        { Key.get =
            (fun key ->
              let univ = Hashtbl.find_exn results key.id in
              Univ.match_exn univ key.univ_key)
        }
      in
      G.Parallel.iter t.graph ~jobs ~command:(fun ~pred:_ vertex ->
        let (T node) = Hashtbl.find_exn t.nodes vertex in
        let job = node.f getter in
        let%map.Job result = job in
        Hashtbl.add_exn
          results
          ~key:node.key.id
          ~data:(Univ.create node.key.univ_key result);
        ());
      t.get_root getter
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
          G.add_edge graph vertex parent);
        vertex
    in
    let deps, get_root = get t in
    List.iter deps ~f:(fun dep -> ignore (aux dep : Vertex.t));
    { Compiled.nodes; graph; get_root }
  ;;

  let run t ~jobs = compile t |> Compiled.run ~jobs

  module Let_syntax = struct
    module Let_syntax = struct
      let map x ~f = map x ~f
      let bind x ~f = spawn x ~f
      let both = both
    end
  end
end
