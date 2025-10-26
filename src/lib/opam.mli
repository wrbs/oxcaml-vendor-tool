open! Core

(** Monadic/JS-y interfaces around opam stuff *)

module Package : sig
  module Name : sig
    type t = OpamPackage.Name.t

    include Identifiable.S_not_binable with type t := t
  end

  module Version : sig
    type t = OpamPackage.Version.t

    include Identifiable.S_not_binable with type t := t
  end

  type t = OpamPackage.t

  include Identifiable.S_not_binable with type t := t
end

module Url : sig
  type t = OpamUrl.t [@@deriving string, sexp, compare]
end

module Hash : sig
  type t = OpamHash.t [@@deriving string, sexp, compare]
end

module Relop : sig
  type t = OpamTypes.relop [@@deriving sexp, compare]
end

module Version_constraint : sig
  type t = OpamFormula.version_constraint [@@deriving sexp, compare]

  val exact : Package.Version.t -> t
end

module Opam_file_url : sig
  type t = OpamFile.URL.t [@@deriving sexp_of]
end

module Filter : sig
  type t = OpamTypes.filter [@@deriving sexp_of, compare]
end

module Filtered : sig
  type 'a t = 'a * Filter.t option [@@deriving sexp_of, compare]
end

module Job : sig
  type 'a t = 'a OpamProcess.job

  include Monad.S with type 'a t := 'a t

  val run : 'a t -> 'a
  val command : OpamProcess.command -> OpamProcess.result t
end

module Par : sig
  type 'a t

  (* Execution *)

  val run : 'a t -> jobs:int -> ('a, unit) Result.t
  val run_exn : 'a t -> jobs:int -> 'a

  (** Main sources of parallelism *)

  val all : 'a t list -> 'a list t
  val all_unit : 'a t list -> unit t

  (** Combinators  *)

  val return : 'a -> 'a t
  val job : ?desc:string -> 'a Job.t -> 'a t
  val spawn : ?desc:string -> 'a t -> f:('a -> 'b Job.t) -> 'b t
  val map : ?desc:string -> 'a t -> f:('a -> 'b) -> 'b t
  val both : 'a t -> 'b t -> ('a * 'b) t

  (** Maps an output without actually making a new node in the graph:
      each time the value is needed by some other node it will be recomputed *)
  val uncached_map : 'a t -> f:('a -> 'b) -> 'b t

  (** Ignores the result of a computation, but still keeps it as a dependency;
      doesn't make a new node *)
  val ignore : 'a t -> unit t

  (** Failure *)

  type 'a command_output =
    | Expect_none : unit command_output
    | Ignore : unit command_output
    | Return : string list command_output

  val command_or_fail : OpamProcess.command -> output:'a command_output -> 'a Job.t

  val fail
    :  ?extra:
         [ `msg of string
         | `raw of string
         | `error of Error.t
         | `exn of exn
         | `exn_backtrace of exn
         ]
    -> ('a, unit, string, _) format4
    -> 'a

  val fail_details : ('a, unit, string, ('b, unit, string, _) format4 -> 'b) format4 -> 'a

  (* Compilation *)
  module Compiled : sig
    type 'a t

    val run : 'a t -> jobs:int -> ('a, unit) Result.t
    val run_exn : 'a t -> jobs:int -> 'a
    val output_dot : _ t -> Out_channel.t -> unit
    val json : _ t -> string
  end

  val compile : 'a t -> 'a Compiled.t

  module Let_syntax : sig
    module Let_syntax : sig
      val map : 'a t -> f:('a -> 'b) -> 'b t
      val bind : 'a t -> f:('a -> 'b Job.t) -> 'b t
      val both : 'a t -> 'b t -> ('a * 'b) t
    end
  end

  module Desc : sig
    module Let_syntax : sig
      module Let_syntax : sig
        val map : string * 'a t -> f:('a -> 'b) -> 'b t
        val bind : string * 'a t -> f:('a -> 'b Job.t) -> 'b t
        val both : 'a t -> string * 'b t -> string * ('a * 'b) t
      end
    end
  end
end
