(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2012     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* Thread safe queue with some extras *)

type 'a t
val create : unit -> 'a t
val pop : 'a t -> 'a
val push : 'a t -> 'a -> unit
val set_order : 'a t -> ('a -> 'a -> int) -> unit
val wait_until_n_are_waiting_and_queue_empty : int -> 'a t -> unit
val dump : 'a t -> 'a list
val clear : 'a t -> unit
val is_empty : 'a t -> bool

exception BeingDestroyed
(* Threads blocked in pop can get this exception if the queue is being
 * destroyed *)
val destroy : 'a t -> unit
