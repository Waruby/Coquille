(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2012     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

open Pp
open Util
open Errors
open Names
open Locus
open Context
open Term
open Nameops
open Termops
open Pretype_errors

(** Processing occurrences *)

type occurrence_error =
  | InvalidOccurrence of int list
  | IncorrectInValueOccurrence of Id.t

let explain_invalid_occurrence l =
  let l = List.sort_uniquize Int.compare l in
  str ("Invalid occurrence " ^ String.plural (List.length l) "number" ^": ")
  ++ prlist_with_sep spc int l ++ str "."

let explain_incorrect_in_value_occurrence id =
  pr_id id ++ str " has no value."

let explain_occurrence_error = function
  | InvalidOccurrence l -> explain_invalid_occurrence l
  | IncorrectInValueOccurrence id -> explain_incorrect_in_value_occurrence id

let error_occurrences_error e =
  errorlabstrm "" (explain_occurrence_error e)

let error_invalid_occurrence occ =
  error_occurrences_error (InvalidOccurrence occ)

let check_used_occurrences nbocc (nowhere_except_in,locs) =
  let rest = List.filter (fun o -> o >= nbocc) locs in
  match rest with
  | [] -> ()
  | _ -> error_occurrences_error (InvalidOccurrence rest)

let proceed_with_occurrences f occs x =
  match occs with
  | NoOccurrences -> x
  | _ ->
    (* TODO FINISH ADAPTING WITH HUGO *)
    let plocs = Locusops.convert_occs occs in
    assert (List.for_all (fun x -> x >= 0) (snd plocs));
    let (nbocc,x) = f 1 x in
    check_used_occurrences nbocc plocs;
    x

(** Applying a function over a named_declaration with an hypothesis
    location request *)

let map_named_declaration_with_hyploc f hyploc acc (id,bodyopt,typ) =
  let f = f (Some (id,hyploc)) in
  match bodyopt,hyploc with
  | None, InHypValueOnly ->
      error_occurrences_error (IncorrectInValueOccurrence id)
  | None, _ | Some _, InHypTypeOnly ->
      let acc,typ = f acc typ in acc,(id,bodyopt,typ)
  | Some body, InHypValueOnly ->
      let acc,body = f acc body in acc,(id,Some body,typ)
  | Some body, InHyp ->
      let acc,body = f acc body in
      let acc,typ = f acc typ in
      acc,(id,Some body,typ)

(** Finding a subterm up to some testing function *)

exception SubtermUnificationError of subterm_unification_error

exception NotUnifiable of (constr * constr * unification_error) option

type 'a testing_function = {
  match_fun : 'a -> constr -> 'a;
  merge_fun : 'a -> 'a -> 'a;
  mutable testing_state : 'a;
  mutable last_found : ((Id.t * hyp_location_flag) option * int * constr) option
}

(* Find subterms using a testing function, but only at a list of
   locations or excluding a list of locations; in the occurrences list
   (b,l), b=true means no occurrence except the ones in l and b=false,
   means all occurrences except the ones in l *)

let replace_term_occ_gen_modulo occs test bywhat cl occ t =
  let (nowhere_except_in,locs) = Locusops.convert_occs occs in
  let maxocc = List.fold_right max locs 0 in
  let pos = ref occ in
  let nested = ref false in
  let add_subst t subst =
    try
      test.testing_state <- test.merge_fun subst test.testing_state;
      test.last_found <- Some (cl,!pos,t)
    with NotUnifiable e ->
      let lastpos = Option.get test.last_found in
     raise (SubtermUnificationError (!nested,(cl,!pos,t),lastpos,e)) in
  let rec substrec k t =
    if nowhere_except_in && !pos > maxocc then t else
    if not (Vars.closed0 t) then subst_below k t else
    try
      let subst = test.match_fun test.testing_state t in
      if Locusops.is_selected !pos occs then
        (add_subst t subst; incr pos;
         (* Check nested matching subterms *)
         nested := true; ignore (subst_below k t); nested := false;
         (* Do the effective substitution *)
         Vars.lift k (bywhat ()))
      else
        (incr pos; subst_below k t)
    with NotUnifiable _ ->
      subst_below k t
  and subst_below k t =
    map_constr_with_binders_left_to_right (fun d k -> k+1) substrec k t
  in
  let t' = substrec 0 t in
  (!pos, t')

let replace_term_occ_modulo occs test bywhat t =
  proceed_with_occurrences
    (replace_term_occ_gen_modulo occs test bywhat None) occs t

let replace_term_occ_decl_modulo (plocs,hyploc) test bywhat d =
  proceed_with_occurrences
    (map_named_declaration_with_hyploc
       (replace_term_occ_gen_modulo plocs test bywhat)
       hyploc)
    plocs d

(** Finding an exact subterm *)

let make_eq_univs_test env evd c =
  { match_fun = (fun evd c' ->
    let b, cst = Universes.eq_constr_universes_proj env c c' in
      if b then
	try Evd.add_universe_constraints evd cst
	with Evd.UniversesDiffer -> raise (NotUnifiable None)
      else raise (NotUnifiable None));
  merge_fun = (fun evd _ -> evd);
  testing_state = evd;
  last_found = None
} 

let subst_closed_term_occ env evd occs c t =
  let test = make_eq_univs_test env evd c in
  let bywhat () = mkRel 1 in
  let t' = replace_term_occ_modulo occs test bywhat t in
    t', test.testing_state

let subst_closed_term_occ_decl env evd (plocs,hyploc) c d =
  let test = make_eq_univs_test env evd c in
  let bywhat () = mkRel 1 in
  proceed_with_occurrences
    (map_named_declaration_with_hyploc
       (fun _ -> replace_term_occ_gen_modulo plocs test bywhat None)
       hyploc) plocs d,
  test.testing_state
