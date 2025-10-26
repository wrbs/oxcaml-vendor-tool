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
  (** A graph-building interface around [OpamParallel] that makes it way easier
     to mix up types.

     Unlike a general monad, you must commit to the 'shape' of the graph
     upfront, but you can execute different jobs based on the outputs in the
     graph. This is why there's no [bind].
     
     The [?desc] arguments are used to annotate the jobs in the compiled graph's
     json or dot output/label failure messages if present *)

  type 'a t

  (* Execution *)

  val run : 'a t -> jobs:int -> ('a, unit) Result.t
  val run_exn : 'a t -> jobs:int -> 'a

  (** Main sources of parallelism *)

  val all : 'a t list -> 'a list t
  val all_unit : 'a t list -> unit t

  (** Returns a value. Does not make a new node*)
  val return : 'a -> 'a t

  (** Main 'bind'-like interface: [spawn t ~f] creates a new node depending on
      everything used to produce [t] that runs [f] on the value of [t] when ran *)
  val spawn : ?desc:string -> 'a t -> f:('a -> 'b Job.t) -> 'b t

  (** Helper for jobs with no dependencies *)
  val job : ?desc:string -> 'a Job.t -> 'a t

  (** Map a value. Does not make a new node for constants but otherwise does 
      (i.e. the output is cached as part of the graph) *)
  val map : ?desc:string -> 'a t -> f:('a -> 'b) -> 'b t

  (** Maps an output without actually making a new node in the graph:
      each time the value is needed by some other node it will be recomputed *)
  val uncached_map : 'a t -> f:('a -> 'b) -> 'b t

  (** Ignores the result of a computation, but still keeps it as a dependency;
      doesn't make a new node *)
  val ignore : 'a t -> unit t

  (** Combines two values, never makes a new node *)
  val both : 'a t -> 'b t -> ('a * 'b) t

  (** Failure; raises exceptions that will be shown in the console nicely.

      Unhandled exceptions turn into a version of this with a backtrace.
  
      If a node fails, every node that depends on it will be skipped. *)

  (** [fail "message %s" "args..." ] raises a failure with main log message
       given by the format string.

      [extra] if present is shown when printing error details at the end of execution *)
  val fail
    :  ?extra:
         [ `msg of string (* is autoformatted *)
         | `raw of string (* passed raw, no ending newline *)
         | `error of Error.t (* formats error sexp *)
         | `exn of exn (* shows exception without backtrace *)
         | `exn_backtrace of exn (* shows exception + backtrace *)
         ]
    -> ('a, unit, string, _) format4
    -> 'a

  (** Raise a failure with string details.

     Syntax:
     
    - {[fail_details "message without args" "details without args"]}
    - {[fail_details "message: %s %s" "arg1" "arg2" "details: %s" "arg"]} *)
  val fail_details : ('a, unit, string, ('b, unit, string, _) format4 -> 'b) format4 -> 'a

  (** Commands: raises failures on non-0 exit status.
  
      Failure details have stdout/stderr/exit code.  *)

  type 'a command_output =
    | Expect_none : unit command_output (* fails if non-empty *)
    | Ignore : unit command_output
    | Return : string list command_output

  val command_or_fail : OpamProcess.command -> output:'a command_output -> 'a Job.t

  module Compiled : sig
    (** A compiled graph. You can print it out for graphviz/as json. 
    
      The main [run] is the same as [compile t |> Compiled.run] *)

    type 'a t

    val run : 'a t -> jobs:int -> ('a, unit) Result.t
    val run_exn : 'a t -> jobs:int -> 'a
    val output_dot : _ t -> Out_channel.t -> unit
    val json : _ t -> string
  end

  val compile : 'a t -> 'a Compiled.t

  (** In let syntax, [bind] is actually 'spawn' *)
  module Let_syntax : sig
    module Let_syntax : sig
      val map : 'a t -> f:('a -> 'b) -> 'b t
      val bind : 'a t -> f:('a -> 'b Job.t) -> 'b t
      val both : 'a t -> 'b t -> ('a * 'b) t
    end
  end

  (** Allows using descriptions and let syntax. Syntax:

  {[let%bind.Opam.Par.Desc x = "desc", x_par in]}

  {[let%map.Opam.Par.Desc x = x_par
    and y = y_par 
    and z = "desc", z_par in]} *)
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
