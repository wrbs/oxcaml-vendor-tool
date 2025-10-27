open! Core
open Oxcaml_vendor_tool_lib

let std_env = Opam_0install.Dir_context.std_env

type rejection =
  | User_constraint of Opam.Package.Name.t * Opam.Version_constraint.t
  | Unavailable

let pp_rejection f = function
  | User_constraint (name, constraint_) ->
    Fmt.pf
      f
      "Rejected by user-specified constraint %s"
      (OpamFormula.string_of_atom (name, Some constraint_))
  | Unavailable -> Fmt.string f "Availability condition not satisfied"
;;

let list_dir path =
  try Sys_unix.ls_dir path with
  | _ -> []
;;

module Package = struct
  module T = struct
    type t = OpamPackage.t [@@deriving compare, string]

    include Sexpable.Of_stringable (struct
        type nonrec t = t [@@deriving string]
      end)

    let hash t = [%hash: string] (to_string t)
    let hash_fold_t state t = [%hash_fold: string] state (to_string t)
  end

  include T
  include Comparable.Make (T)
  include Hashable.Make (T)
end

module Package_source = struct
  type t =
    { repo : Repo.t
    ; version_dir : string
    }
end

type t =
  { env : string -> OpamVariable.variable_contents option
  ; project : Project.t
  ; repos : Repo.t list
  ; pins : (OpamPackage.Version.t * OpamFile.OPAM.t) OpamPackage.Name.Map.t
  ; constraints : OpamFormula.version_constraint OpamPackage.Name.Map.t
  ; test : OpamPackage.Name.Set.t
  ; package_sources : Package_source.t Package.Table.t
  }

let load_packages t name =
  List.concat_map t.repos ~f:(fun repo ->
    let versions_dir =
      Repo.dir repo ~project:t.project ^/ "packages" ^/ OpamPackage.Name.to_string name
    in
    List.filter_map (list_dir versions_dir) ~f:(fun version_dir ->
      let%bind.Option package = OpamPackage.of_string_opt version_dir in
      let package_dir = versions_dir ^/ version_dir in
      let opam_file_path = package_dir ^/ "opam" in
      match Sys_unix.file_exists_exn opam_file_path with
      | false -> None
      | true ->
        (match Hashtbl.mem t.package_sources package with
         | true -> None (* seen in some other repo *)
         | false ->
           Hashtbl.add_exn t.package_sources ~key:package ~data:{ repo; version_dir };
           Some (OpamPackage.version package, opam_file_path)))
    |> List.sort
         ~compare:
           (Comparable.reverse
              (Comparable.lift [%compare: OpamPackage.Version.t] ~f:Tuple2.get1)))
;;

let env t pkg v =
  if Stdlib.List.mem v OpamPackageVar.predefined_depends_variables
  then None
  else (
    match OpamVariable.Full.to_string v with
    | "version" ->
      Some (OpamTypes.S (OpamPackage.Version.to_string (OpamPackage.version pkg)))
    | x -> t.env x)
;;

let dev = OpamPackage.Version.of_string "dev"

let filter_deps t pkg f =
  let dev = OpamPackage.Version.compare (OpamPackage.version pkg) dev = 0 in
  let test = OpamPackage.Name.Set.mem (OpamPackage.name pkg) t.test in
  f
  |> OpamFilter.partial_filter_formula (env t pkg)
  |> OpamFilter.filter_deps
       ~build:true
       ~post:true
       ~test
       ~doc:false
       ~dev
       ~dev_setup:false
       ~default:false
;;

let user_restrictions t package = OpamPackage.Name.Map.find_opt package t.constraints

let candidates t name =
  match OpamPackage.Name.Map.find_opt name t.pins with
  | Some (version, opam) -> [ version, Ok opam ]
  | None ->
    (match load_packages t name with
     | [] ->
       OpamConsole.log
         "opam-0install"
         "Package %S not found!"
         (OpamPackage.Name.to_string name);
       []
     | versions ->
       List.map versions ~f:(fun (version, opam_file_path) ->
         let result =
           match user_restrictions t name with
           | Some formula
             when not (OpamFormula.check_version_formula (Atom formula) version) ->
             Error (User_constraint (name, formula))
           | _ ->
             let pkg = OpamPackage.create name version in
             let opam =
               OpamFile.OPAM.read (OpamFile.make (OpamFilename.raw opam_file_path))
             in
             let available = OpamFile.OPAM.available opam in
             (match OpamFilter.eval ~default:(B false) (env t pkg) available with
              | B true -> Ok opam
              | B false -> Error Unavailable
              | _ ->
                OpamConsole.error
                  "Available expression not a boolean: %s"
                  (OpamFilter.to_string available);
                Error Unavailable)
         in
         version, result))
;;

let create
      ?(test = OpamPackage.Name.Set.empty)
      ?(pins = OpamPackage.Name.Map.empty)
      repos
      ~project
      ~constraints
      ~env
  =
  { env
  ; project
  ; repos
  ; pins
  ; constraints
  ; test
  ; package_sources = Package.Table.create ()
  }
;;

let package_source t package = Hashtbl.find_exn t.package_sources package
