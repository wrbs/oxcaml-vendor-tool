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

module Version_formula : sig
  type t = OpamFormula.version_formula [@@deriving sexp, compare]

  val exact : Package.Version.t -> t
end

module Job : sig
  type 'a t = 'a OpamProcess.job

  include Monad.S with type 'a t := 'a t

  val run : 'a t -> 'a
end

module Opam_file : sig
  type t = OpamFile.OPAM.t [@@deriving sexp_of]
end

module Filter : sig
  type t = OpamTypes.filter [@@deriving sexp]
end

module Filtered : sig
  type 'a t = 'a * OpamTypes.filter option [@@deriving sexp]
end

module Par : sig
  type 'a t

  (* Execution *)

  val run : 'a t -> jobs:int -> 'a

  (** Main sources of parallelism *)

  val all : 'a t list -> 'a list t
  val all_unit : 'a t list -> unit t

  (** Combinators  *)

  val return : 'a -> 'a t
  val job : ?desc:string -> 'a Job.t -> 'a t
  val spawn : ?desc:string -> 'a t -> f:('a -> 'b Job.t) -> 'b t
  val map : ?desc:string -> 'a t -> f:('a -> 'b) -> 'b t
  val both : 'a t -> 'b t -> ('a * 'b) t

  (* Compilation *)
  module Compiled : sig
    type 'a t

    val run : 'a t -> jobs:int -> 'a
    val output_dot : _ t -> Out_channel.t -> unit
  end

  val compile : 'a t -> 'a Compiled.t

  module Let_syntax : sig
    module Let_syntax : sig
      val map : 'a t -> f:('a -> 'b) -> 'b t
      val bind : 'a t -> f:('a -> 'b Job.t) -> 'b t
      val both : 'a t -> 'b t -> ('a * 'b) t
    end
  end
end
