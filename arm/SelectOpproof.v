(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(* *********************************************************************)

(** Correctness of instruction selection for operators *)

Require Import Coqlib.
Require Import Maps.
Require Import AST.
Require Import Integers.
Require Import Floats.
Require Import Values.
Require Import Memory.
Require Import Events.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Cminor.
Require Import Op.
Require Import CminorSel.
Require Import SelectOp.

Open Local Scope cminorsel_scope.

Section CMCONSTR.

Variable ge: genv.
Variable sp: val.
Variable e: env.
Variable m: mem.

(** * Useful lemmas and tactics *)

(** The following are trivial lemmas and custom tactics that help
  perform backward (inversion) and forward reasoning over the evaluation
  of operator applications. *)  

Ltac EvalOp := eapply eval_Eop; eauto with evalexpr.

Ltac TrivialOp cstr := unfold cstr; intros; EvalOp.

Ltac InvEval1 :=
  match goal with
  | [ H: (eval_expr _ _ _ _ _ (Eop _ Enil) _) |- _ ] =>
      inv H; InvEval1
  | [ H: (eval_expr _ _ _ _ _ (Eop _ (_ ::: Enil)) _) |- _ ] =>
      inv H; InvEval1
  | [ H: (eval_expr _ _ _ _ _ (Eop _ (_ ::: _ ::: Enil)) _) |- _ ] =>
      inv H; InvEval1
  | [ H: (eval_exprlist _ _ _ _ _ Enil _) |- _ ] =>
      inv H; InvEval1
  | [ H: (eval_exprlist _ _ _ _ _ (_ ::: _) _) |- _ ] =>
      inv H; InvEval1
  | _ =>
      idtac
  end.

Ltac InvEval2 :=
  match goal with
  | [ H: (eval_operation _ _ _ nil = Some _) |- _ ] =>
      simpl in H; inv H
  | [ H: (eval_operation _ _ _ (_ :: nil) = Some _) |- _ ] =>
      simpl in H; FuncInv
  | [ H: (eval_operation _ _ _ (_ :: _ :: nil) = Some _) |- _ ] =>
      simpl in H; FuncInv
  | [ H: (eval_operation _ _ _ (_ :: _ :: _ :: nil) = Some _) |- _ ] =>
      simpl in H; FuncInv
  | _ =>
      idtac
  end.

Ltac InvEval := InvEval1; InvEval2; InvEval2.

(** * Correctness of the smart constructors *)

(** We now show that the code generated by "smart constructor" functions
  such as [Selection.notint] behaves as expected.  Continuing the
  [notint] example, we show that if the expression [e]
  evaluates to some integer value [Vint n], then [Selection.notint e]
  evaluates to a value [Vint (Int.not n)] which is indeed the integer
  negation of the value of [e].

  All proofs follow a common pattern:
- Reasoning by case over the result of the classification functions
  (such as [add_match] for integer addition), gathering additional
  information on the shape of the argument expressions in the non-default
  cases.
- Inversion of the evaluations of the arguments, exploiting the additional
  information thus gathered.
- Equational reasoning over the arithmetic operations performed,
  using the lemmas from the [Int] and [Float] modules.
- Construction of an evaluation derivation for the expression returned
  by the smart constructor.
*)

Theorem eval_notint:
  forall le a x,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le (notint a) (Vint (Int.not x)).
Proof.
  unfold notint; intros until x; case (notint_match a); intros; InvEval.
  EvalOp. simpl. congruence.
  subst x. rewrite Int.not_involutive.  auto.
  EvalOp. simpl. subst x. rewrite Int.not_involutive. auto.
  EvalOp.
Qed.

Lemma eval_notbool_base:
  forall le a v b,
  eval_expr ge sp e m le a v ->
  Val.bool_of_val v b ->
  eval_expr ge sp e m le (notbool_base a) (Val.of_bool (negb b)).
Proof. 
  TrivialOp notbool_base. simpl. 
  inv H0. 
  rewrite Int.eq_false; auto.
  rewrite Int.eq_true; auto.
  reflexivity.
Qed.

Hint Resolve Val.bool_of_true_val Val.bool_of_false_val
             Val.bool_of_true_val_inv Val.bool_of_false_val_inv: valboolof.

Theorem eval_notbool:
  forall le a v b,
  eval_expr ge sp e m le a v ->
  Val.bool_of_val v b ->
  eval_expr ge sp e m le (notbool a) (Val.of_bool (negb b)).
Proof.
  induction a; simpl; intros; try (eapply eval_notbool_base; eauto).
  destruct o; try (eapply eval_notbool_base; eauto).

  destruct e0. InvEval. 
  inv H0. rewrite Int.eq_false; auto. 
  simpl; eauto with evalexpr.
  rewrite Int.eq_true; simpl; eauto with evalexpr.
  eapply eval_notbool_base; eauto.

  inv H. eapply eval_Eop; eauto.
  simpl. assert (eval_condition c vl = Some b).
  generalize H6. simpl. 
  case (eval_condition c vl); intros.
  destruct b0; inv H1; inversion H0; auto; congruence.
  congruence.
  rewrite (Op.eval_negate_condition _ _ H). 
  destruct b; reflexivity.

  inv H. eapply eval_Econdition; eauto. 
  destruct v1; eauto.
Qed.

Theorem eval_addimm:
  forall le n a x,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le (addimm n a) (Vint (Int.add x n)).
Proof.
  unfold addimm; intros until x.
  generalize (Int.eq_spec n Int.zero). case (Int.eq n Int.zero); intro.
  subst n. rewrite Int.add_zero. auto.
  case (addimm_match a); intros; InvEval; EvalOp; simpl.
  rewrite Int.add_commut. auto.
  destruct (Genv.find_symbol ge s); discriminate.
  destruct sp; simpl in H1; discriminate.
  subst x. rewrite Int.add_assoc. decEq; decEq; decEq. apply Int.add_commut.
Qed. 

Theorem eval_addimm_ptr:
  forall le n a b ofs,
  eval_expr ge sp e m le a (Vptr b ofs) ->
  eval_expr ge sp e m le (addimm n a) (Vptr b (Int.add ofs n)).
Proof.
  unfold addimm; intros until ofs.
  generalize (Int.eq_spec n Int.zero). case (Int.eq n Int.zero); intro.
  subst n. rewrite Int.add_zero. auto.
  case (addimm_match a); intros; InvEval; EvalOp; simpl.
  destruct (Genv.find_symbol ge s). 
  rewrite Int.add_commut. congruence.
  discriminate.
  destruct sp; simpl in H1; try discriminate.
  inv H1. simpl. decEq. decEq. 
  rewrite Int.add_assoc. decEq. apply Int.add_commut.
  subst. rewrite (Int.add_commut n m0). rewrite Int.add_assoc. auto.
Qed.

Theorem eval_add:
  forall le a b x y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (add a b) (Vint (Int.add x y)).
Proof.
  intros until y.
  unfold add; case (add_match a b); intros; InvEval.
  rewrite Int.add_commut. apply eval_addimm. auto. 
  replace (Int.add x y) with (Int.add (Int.add i0 i) (Int.add n1 n2)).
    apply eval_addimm. EvalOp.  
    subst x; subst y. 
    repeat rewrite Int.add_assoc. decEq. apply Int.add_permut. 
  replace (Int.add x y) with (Int.add (Int.add i y) n1).
    apply eval_addimm. EvalOp.
    subst x. repeat rewrite Int.add_assoc. decEq. apply Int.add_commut.
  apply eval_addimm. auto.
  replace (Int.add x y) with (Int.add (Int.add x i) n2).
    apply eval_addimm. EvalOp.
    subst y. rewrite Int.add_assoc. auto.
  EvalOp. simpl. subst x. rewrite Int.add_commut. auto.
  EvalOp. simpl. congruence.
  EvalOp.
Qed.

Theorem eval_add_ptr:
  forall le a b p x y,
  eval_expr ge sp e m le a (Vptr p x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (add a b) (Vptr p (Int.add x y)).
Proof.
  intros until y. unfold add; case (add_match a b); intros; InvEval.
  replace (Int.add x y) with (Int.add (Int.add i0 i) (Int.add n1 n2)).
    apply eval_addimm_ptr. subst b0. EvalOp. 
    subst x; subst y.
    repeat rewrite Int.add_assoc. decEq. apply Int.add_permut. 
  replace (Int.add x y) with (Int.add (Int.add i y) n1).
    apply eval_addimm_ptr. subst b0. EvalOp.
    subst x. repeat rewrite Int.add_assoc. decEq. apply Int.add_commut.
  apply eval_addimm_ptr. auto.
  replace (Int.add x y) with (Int.add (Int.add x i) n2).
    apply eval_addimm_ptr. EvalOp.
    subst y. rewrite Int.add_assoc. auto.
  EvalOp. simpl. congruence.
  EvalOp.
Qed.

Theorem eval_add_ptr_2:
  forall le a b x p y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vptr p y) ->
  eval_expr ge sp e m le (add a b) (Vptr p (Int.add y x)).
Proof.
  intros until y. unfold add; case (add_match a b); intros; InvEval.
  apply eval_addimm_ptr. auto.
  replace (Int.add y x) with (Int.add (Int.add i i0) (Int.add n1 n2)).
    apply eval_addimm_ptr. subst b0. EvalOp. 
    subst x; subst y.
    repeat rewrite Int.add_assoc. decEq. 
    rewrite (Int.add_commut n1 n2). apply Int.add_permut. 
  replace (Int.add y x) with (Int.add (Int.add y i) n1).
    apply eval_addimm_ptr. EvalOp. 
    subst x. repeat rewrite Int.add_assoc. auto.
  replace (Int.add y x) with (Int.add (Int.add i x) n2).
    apply eval_addimm_ptr. EvalOp. subst b0; reflexivity.
    subst y. repeat rewrite Int.add_assoc. decEq. apply Int.add_commut.
  EvalOp. simpl. congruence.
  EvalOp.
Qed.

Theorem eval_sub:
  forall le a b x y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (sub a b) (Vint (Int.sub x y)).
Proof.
  intros until y.
  unfold sub; case (sub_match a b); intros; InvEval.
  rewrite Int.sub_add_opp. 
    apply eval_addimm. assumption.
  replace (Int.sub x y) with (Int.add (Int.sub i0 i) (Int.sub n1 n2)).
    apply eval_addimm. EvalOp.
    subst x; subst y.
    repeat rewrite Int.sub_add_opp.
    repeat rewrite Int.add_assoc. decEq. 
    rewrite Int.add_permut. decEq. symmetry. apply Int.neg_add_distr.
  replace (Int.sub x y) with (Int.add (Int.sub i y) n1).
    apply eval_addimm. EvalOp.
    subst x. rewrite Int.sub_add_l. auto.
  replace (Int.sub x y) with (Int.add (Int.sub x i) (Int.neg n2)).
    apply eval_addimm. EvalOp.
    subst y. rewrite (Int.add_commut i n2). symmetry. apply Int.sub_add_r.
  EvalOp. 
  EvalOp. simpl. congruence.
  EvalOp. simpl. congruence.
  EvalOp.
Qed.

Theorem eval_sub_ptr_int:
  forall le a b p x y,
  eval_expr ge sp e m le a (Vptr p x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (sub a b) (Vptr p (Int.sub x y)).
Proof.
  intros until y.
  unfold sub; case (sub_match a b); intros; InvEval.
  rewrite Int.sub_add_opp. 
    apply eval_addimm_ptr. assumption.
  subst b0. replace (Int.sub x y) with (Int.add (Int.sub i0 i) (Int.sub n1 n2)).
    apply eval_addimm_ptr. EvalOp.
    subst x; subst y.
    repeat rewrite Int.sub_add_opp.
    repeat rewrite Int.add_assoc. decEq. 
    rewrite Int.add_permut. decEq. symmetry. apply Int.neg_add_distr.
  subst b0. replace (Int.sub x y) with (Int.add (Int.sub i y) n1).
    apply eval_addimm_ptr. EvalOp.
    subst x. rewrite Int.sub_add_l. auto.
  replace (Int.sub x y) with (Int.add (Int.sub x i) (Int.neg n2)).
    apply eval_addimm_ptr. EvalOp.
    subst y. rewrite (Int.add_commut i n2). symmetry. apply Int.sub_add_r.
  EvalOp. simpl. congruence.  
  EvalOp.
Qed.

Theorem eval_sub_ptr_ptr:
  forall le a b p x y,
  eval_expr ge sp e m le a (Vptr p x) ->
  eval_expr ge sp e m le b (Vptr p y) ->
  eval_expr ge sp e m le (sub a b) (Vint (Int.sub x y)).
Proof.
  intros until y.
  unfold sub; case (sub_match a b); intros; InvEval.
  replace (Int.sub x y) with (Int.add (Int.sub i0 i) (Int.sub n1 n2)).
    apply eval_addimm. EvalOp. 
    simpl; unfold eq_block. subst b0; subst b1; rewrite zeq_true. auto.
    subst x; subst y.
    repeat rewrite Int.sub_add_opp.
    repeat rewrite Int.add_assoc. decEq. 
    rewrite Int.add_permut. decEq. symmetry. apply Int.neg_add_distr.
  subst b0. replace (Int.sub x y) with (Int.add (Int.sub i y) n1).
    apply eval_addimm. EvalOp.
    simpl. unfold eq_block. rewrite zeq_true. auto.
    subst x. rewrite Int.sub_add_l. auto.
  subst b0. replace (Int.sub x y) with (Int.add (Int.sub x i) (Int.neg n2)).
    apply eval_addimm. EvalOp.
    simpl. unfold eq_block. rewrite zeq_true. auto.
    subst y. rewrite (Int.add_commut i n2). symmetry. apply Int.sub_add_r. 
  EvalOp. simpl. unfold eq_block. rewrite zeq_true. auto.
Qed.

Theorem eval_shlimm:
  forall le a n x,
  eval_expr ge sp e m le a (Vint x) ->
  Int.ltu n Int.iwordsize = true ->
  eval_expr ge sp e m le (shlimm a n) (Vint (Int.shl x n)).
Proof.
  intros until x.  unfold shlimm, is_shift_amount.
  generalize (Int.eq_spec n Int.zero); case (Int.eq n Int.zero); intro.
  intros. subst n. rewrite Int.shl_zero. auto.
  destruct (is_shift_amount_aux n). simpl. 
  case (shlimm_match a); intros; InvEval.
  EvalOp.
  destruct (is_shift_amount_aux (Int.add n (s_amount n1))).
  EvalOp. simpl. subst x.
  decEq. decEq. symmetry. rewrite Int.add_commut. apply Int.shl_shl.
  apply s_amount_ltu. auto.
  rewrite Int.add_commut. auto.
  EvalOp. econstructor. EvalOp. simpl. reflexivity. constructor.
  simpl. congruence.
  EvalOp.
  congruence. 
Qed.

Theorem eval_shruimm:
  forall le a n x,
  eval_expr ge sp e m le a (Vint x) ->
  Int.ltu n Int.iwordsize = true ->
  eval_expr ge sp e m le (shruimm a n) (Vint (Int.shru x n)).
Proof.
  intros until x.  unfold shruimm, is_shift_amount.
  generalize (Int.eq_spec n Int.zero); case (Int.eq n Int.zero); intro.
  intros. subst n. rewrite Int.shru_zero. auto.
  destruct (is_shift_amount_aux n). simpl. 
  case (shruimm_match a); intros; InvEval.
  EvalOp.
  destruct (is_shift_amount_aux (Int.add n (s_amount n1))).
  EvalOp. simpl. subst x.
  decEq. decEq. symmetry. rewrite Int.add_commut. apply Int.shru_shru.
  apply s_amount_ltu. auto.
  rewrite Int.add_commut. auto.
  EvalOp. econstructor. EvalOp. simpl. reflexivity. constructor.
  simpl. congruence.
  EvalOp.
  congruence. 
Qed.

Theorem eval_shrimm:
  forall le a n x,
  eval_expr ge sp e m le a (Vint x) ->
  Int.ltu n Int.iwordsize = true ->
  eval_expr ge sp e m le (shrimm a n) (Vint (Int.shr x n)).
Proof.
  intros until x.  unfold shrimm, is_shift_amount.
  generalize (Int.eq_spec n Int.zero); case (Int.eq n Int.zero); intro.
  intros. subst n. rewrite Int.shr_zero. auto.
  destruct (is_shift_amount_aux n). simpl. 
  case (shrimm_match a); intros; InvEval.
  EvalOp.
  destruct (is_shift_amount_aux (Int.add n (s_amount n1))).
  EvalOp. simpl. subst x.
  decEq. decEq. symmetry. rewrite Int.add_commut. apply Int.shr_shr.
  apply s_amount_ltu. auto.
  rewrite Int.add_commut. auto.
  EvalOp. econstructor. EvalOp. simpl. reflexivity. constructor.
  simpl. congruence.
  EvalOp.
  congruence. 
Qed.

Lemma eval_mulimm_base:
  forall le a n x,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le (mulimm_base n a) (Vint (Int.mul x n)).
Proof.
  intros; unfold mulimm_base. 
  generalize (Int.one_bits_decomp n). 
  generalize (Int.one_bits_range n).
  change (Z_of_nat Int.wordsize) with 32.
  destruct (Int.one_bits n).
  intros. EvalOp. constructor. EvalOp. simpl; reflexivity.
  constructor. eauto. constructor. simpl. rewrite Int.mul_commut. auto.
  destruct l.
  intros. rewrite H1. simpl. 
  rewrite Int.add_zero. rewrite <- Int.shl_mul.
  apply eval_shlimm. auto. auto with coqlib. 
  destruct l.
  intros. apply eval_Elet with (Vint x). auto.
  rewrite H1. simpl. rewrite Int.add_zero. 
  rewrite Int.mul_add_distr_r.
  rewrite <- Int.shl_mul.
  rewrite <- Int.shl_mul.
  apply eval_add. 
  apply eval_shlimm. apply eval_Eletvar. simpl. reflexivity. 
  auto with coqlib.
  apply eval_shlimm. apply eval_Eletvar. simpl. reflexivity.
  auto with coqlib.
  intros. EvalOp. constructor. EvalOp. simpl; reflexivity. 
  constructor. eauto. constructor. simpl. rewrite Int.mul_commut. auto.
Qed.

Theorem eval_mulimm:
  forall le a n x,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le (mulimm n a) (Vint (Int.mul x n)).
Proof.
  intros until x; unfold mulimm.
  generalize (Int.eq_spec n Int.zero); case (Int.eq n Int.zero); intro.
  subst n. rewrite Int.mul_zero. 
  intro. EvalOp. 
  generalize (Int.eq_spec n Int.one); case (Int.eq n Int.one); intro.
  subst n. rewrite Int.mul_one. auto.
  case (mulimm_match a); intros; InvEval.
  EvalOp. rewrite Int.mul_commut. reflexivity.
  replace (Int.mul x n) with (Int.add (Int.mul i n) (Int.mul n n2)).
  apply eval_addimm. apply eval_mulimm_base. auto.
  subst x. rewrite Int.mul_add_distr_l. decEq. apply Int.mul_commut.
  apply eval_mulimm_base. assumption.
Qed.

Theorem eval_mul:
  forall le a b x y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (mul a b) (Vint (Int.mul x y)).
Proof.
  intros until y.
  unfold mul; case (mul_match a b); intros; InvEval.
  rewrite Int.mul_commut. apply eval_mulimm. auto. 
  apply eval_mulimm. auto.
  EvalOp.
Qed.

Theorem eval_divs_base:
  forall le a b x y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  y <> Int.zero ->
  eval_expr ge sp e m le (Eop Odiv (a ::: b ::: Enil)) (Vint (Int.divs x y)).
Proof.
  intros. EvalOp; simpl.
  predSpec Int.eq Int.eq_spec y Int.zero. contradiction. auto.
Qed.

Theorem eval_divs:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  y <> Int.zero ->
  eval_expr ge sp e m le (divs a b) (Vint (Int.divs x y)).
Proof.
  intros until y.
  unfold divs; case (divu_match b); intros; InvEval.
  caseEq (Int.is_power2 y); intros.
  caseEq (Int.ltu i (Int.repr 31)); intros.
  EvalOp. simpl. unfold Int.ltu. rewrite zlt_true. 
  rewrite (Int.divs_pow2 x y i H0). auto.
  exploit Int.ltu_inv; eauto. 
  change (Int.unsigned (Int.repr 31)) with 31.
  change (Int.unsigned Int.iwordsize) with 32.
  omega.
  apply eval_divs_base. auto. EvalOp. auto.
  apply eval_divs_base. auto. EvalOp. auto.
  apply eval_divs_base; auto. 
Qed.

Lemma eval_mod_aux:
  forall divop semdivop,
  (forall sp x y,
   y <> Int.zero ->
   eval_operation ge sp divop (Vint x :: Vint y :: nil) =
   Some (Vint (semdivop x y))) ->
  forall le a b x y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  y <> Int.zero ->
  eval_expr ge sp e m le (mod_aux divop a b)
   (Vint (Int.sub x (Int.mul (semdivop x y) y))).
Proof.
  intros; unfold mod_aux.
  eapply eval_Elet. eexact H0. eapply eval_Elet. 
  apply eval_lift. eexact H1.
  eapply eval_Eop. eapply eval_Econs. 
  eapply eval_Eletvar. simpl; reflexivity.
  eapply eval_Econs. eapply eval_Eop. 
  eapply eval_Econs. eapply eval_Eop.
  eapply eval_Econs. apply eval_Eletvar. simpl; reflexivity.
  eapply eval_Econs. apply eval_Eletvar. simpl; reflexivity.
  apply eval_Enil.  
  apply H. assumption.
  eapply eval_Econs. apply eval_Eletvar. simpl; reflexivity.
  apply eval_Enil.  
  simpl; reflexivity. apply eval_Enil. 
  reflexivity.
Qed.

Theorem eval_mods:
  forall le a b x y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  y <> Int.zero ->
  eval_expr ge sp e m le (mods a b) (Vint (Int.mods x y)).
Proof.
  intros; unfold mods. 
  rewrite Int.mods_divs. 
  eapply eval_mod_aux; eauto. 
  intros. simpl. predSpec Int.eq Int.eq_spec y0 Int.zero. 
  contradiction. auto.
Qed.

Lemma eval_divu_base:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  y <> Int.zero ->
  eval_expr ge sp e m le (Eop Odivu (a ::: b ::: Enil)) (Vint (Int.divu x y)).
Proof.
  intros. EvalOp. simpl. 
  predSpec Int.eq Int.eq_spec y Int.zero. contradiction. auto.
Qed.

Theorem eval_divu:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  y <> Int.zero ->
  eval_expr ge sp e m le (divu a b) (Vint (Int.divu x y)).
Proof.
  intros until y.
  unfold divu; case (divu_match b); intros; InvEval.
  caseEq (Int.is_power2 y). 
  intros. rewrite (Int.divu_pow2 x y i H0).
  apply eval_shruimm. auto.
  apply Int.is_power2_range with y. auto.
  intros. apply eval_divu_base. auto. EvalOp. auto.
  eapply eval_divu_base; eauto.
Qed.

Theorem eval_modu:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  y <> Int.zero ->
  eval_expr ge sp e m le (modu a b) (Vint (Int.modu x y)).
Proof.
  intros until y; unfold modu; case (divu_match b); intros; InvEval.
  caseEq (Int.is_power2 y). 
  intros. rewrite (Int.modu_and x y i H0).
  EvalOp. 
  intro. rewrite Int.modu_divu. eapply eval_mod_aux. 
  intros. simpl. predSpec Int.eq Int.eq_spec y0 Int.zero.
  contradiction. auto.
  auto. EvalOp. auto. auto.
  rewrite Int.modu_divu. eapply eval_mod_aux. 
  intros. simpl. predSpec Int.eq Int.eq_spec y0 Int.zero.
  contradiction. auto. auto. auto. auto. auto.
Qed.

Theorem eval_and:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (and a b) (Vint (Int.and x y)).
Proof.
  intros until y; unfold and; case (and_match a b); intros; InvEval.
  rewrite Int.and_commut. EvalOp. simpl. congruence.
  EvalOp. simpl. congruence.
  rewrite Int.and_commut. EvalOp. simpl. congruence.
  EvalOp. simpl. congruence.
  rewrite Int.and_commut. EvalOp. simpl. congruence.
  EvalOp. simpl. congruence.
  EvalOp.
Qed.

Remark eval_same_expr:
  forall a1 a2 le v1 v2,
  same_expr_pure a1 a2 = true ->
  eval_expr ge sp e m le a1 v1 ->
  eval_expr ge sp e m le a2 v2 ->
  a1 = a2 /\ v1 = v2.
Proof.
  intros until v2.
  destruct a1; simpl; try (intros; discriminate). 
  destruct a2; simpl; try (intros; discriminate).
  case (ident_eq i i0); intros.
  subst i0. inversion H0. inversion H1. split. auto. congruence. 
  discriminate.
Qed.

Lemma eval_or:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (or a b) (Vint (Int.or x y)).
Proof.
  intros until y; unfold or; case (or_match a b); intros; InvEval.
  caseEq (Int.eq (Int.add (s_amount n1) (s_amount n2)) Int.iwordsize
          && same_expr_pure t1 t2); intro.
  destruct (andb_prop _ _ H1).
  generalize (Int.eq_spec (Int.add (s_amount n1) (s_amount n2)) Int.iwordsize).
  rewrite H4. intro. 
  exploit eval_same_expr; eauto. intros [EQ1 EQ2]. inv EQ1. inv EQ2. 
  simpl. EvalOp. simpl. decEq. decEq. apply Int.or_ror.
  destruct n1; auto. destruct n2; auto. auto. 
  EvalOp. econstructor. EvalOp. simpl. reflexivity.
  econstructor; eauto with evalexpr. 
  simpl. congruence. 
  EvalOp. simpl. rewrite Int.or_commut. congruence.
  EvalOp. simpl. congruence.
  EvalOp. 
Qed.

Theorem eval_xor:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (xor a b) (Vint (Int.xor x y)).
Proof.
  intros until y; unfold xor; case (xor_match a b); intros; InvEval.
  rewrite Int.xor_commut. EvalOp. simpl. congruence.
  EvalOp. simpl. congruence.
  EvalOp.
Qed.

Theorem eval_shl:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  Int.ltu y Int.iwordsize = true ->
  eval_expr ge sp e m le (shl a b) (Vint (Int.shl x y)).
Proof.
  intros until y; unfold shl; case (shift_match b); intros.
  InvEval. apply eval_shlimm; auto.
  EvalOp. simpl. rewrite H1. auto.
Qed.

Theorem eval_shru:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  Int.ltu y Int.iwordsize = true ->
  eval_expr ge sp e m le (shru a b) (Vint (Int.shru x y)).
Proof.
  intros until y; unfold shru; case (shift_match b); intros.
  InvEval. apply eval_shruimm; auto.
  EvalOp. simpl. rewrite H1. auto.
Qed.

Theorem eval_shr:
  forall le a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  Int.ltu y Int.iwordsize = true ->
  eval_expr ge sp e m le (shr a b) (Vint (Int.shr x y)).
Proof.
  intros until y; unfold shr; case (shift_match b); intros.
  InvEval. apply eval_shrimm; auto.
  EvalOp. simpl. rewrite H1. auto.
Qed.

Theorem eval_cast8signed:
  forall le a v,
  eval_expr ge sp e m le a v ->
  eval_expr ge sp e m le (cast8signed a) (Val.sign_ext 8 v).
Proof. 
  intros until v; unfold cast8signed; case (cast8signed_match a); intros; InvEval.
  EvalOp. simpl. subst v. destruct v1; simpl; auto.
  rewrite Int.sign_ext_idem. reflexivity. vm_compute; auto.
  EvalOp.
Qed.

Theorem eval_cast8unsigned:
  forall le a v,
  eval_expr ge sp e m le a v ->
  eval_expr ge sp e m le (cast8unsigned a) (Val.zero_ext 8 v).
Proof. 
  intros until v; unfold cast8unsigned; case (cast8unsigned_match a); intros; InvEval.
  EvalOp. simpl. subst v. destruct v1; simpl; auto.
  rewrite Int.zero_ext_idem. reflexivity. vm_compute; auto.
  EvalOp.
Qed.

Theorem eval_cast16signed:
  forall le a v,
  eval_expr ge sp e m le a v ->
  eval_expr ge sp e m le (cast16signed a) (Val.sign_ext 16 v).
Proof. 
  intros until v; unfold cast16signed; case (cast16signed_match a); intros; InvEval.
  EvalOp. simpl. subst v. destruct v1; simpl; auto.
  rewrite Int.sign_ext_idem. reflexivity. vm_compute; auto.
  EvalOp.
Qed.

Theorem eval_cast16unsigned:
  forall le a v,
  eval_expr ge sp e m le a v ->
  eval_expr ge sp e m le (cast16unsigned a) (Val.zero_ext 16 v).
Proof. 
  intros until v; unfold cast16unsigned; case (cast16unsigned_match a); intros; InvEval.
  EvalOp. simpl. subst v. destruct v1; simpl; auto.
  rewrite Int.zero_ext_idem. reflexivity. vm_compute; auto.
  EvalOp.
Qed.

Theorem eval_singleoffloat:
  forall le a v,
  eval_expr ge sp e m le a v ->
  eval_expr ge sp e m le (singleoffloat a) (Val.singleoffloat v).
Proof. 
  intros until v; unfold singleoffloat; case (singleoffloat_match a); intros; InvEval.
  EvalOp. simpl. subst v. destruct v1; simpl; auto. rewrite Float.singleoffloat_idem. reflexivity.
  EvalOp.
Qed.

Theorem eval_comp_int:
  forall le c a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (comp c a b) (Val.of_bool(Int.cmp c x y)).
Proof.
  intros until y.
  unfold comp; case (comp_match a b); intros; InvEval.
  EvalOp. simpl. rewrite Int.swap_cmp. destruct (Int.cmp c x y); reflexivity.
  EvalOp. simpl. destruct (Int.cmp c x y); reflexivity.
  EvalOp. simpl. rewrite Int.swap_cmp. rewrite H. destruct (Int.cmp c x y); reflexivity.
  EvalOp. simpl. rewrite H0. destruct (Int.cmp c x y); reflexivity.
  EvalOp. simpl. destruct (Int.cmp c x y); reflexivity.
Qed.

Remark eval_compare_null_trans:
  forall c x v,
  (if Int.eq x Int.zero then Cminor.eval_compare_mismatch c else None) = Some v ->
  match eval_compare_null c x with
  | Some true => Some Vtrue
  | Some false => Some Vfalse
  | None => None (A:=val)
  end = Some v.
Proof.
  unfold Cminor.eval_compare_mismatch, eval_compare_null; intros.
  destruct (Int.eq x Int.zero); try discriminate. 
  destruct c; try discriminate; auto.
Qed.

Theorem eval_comp_ptr_int:
  forall le c a x1 x2 b y v,
  eval_expr ge sp e m le a (Vptr x1 x2) ->
  eval_expr ge sp e m le b (Vint y) ->
  (if Int.eq y Int.zero then Cminor.eval_compare_mismatch c else None) = Some v ->
  eval_expr ge sp e m le (comp c a b) v.
Proof.
  intros until v.
  unfold comp; case (comp_match a b); intros; InvEval.
  EvalOp. simpl. apply eval_compare_null_trans; auto. 
  EvalOp. simpl. rewrite H0. apply eval_compare_null_trans; auto. 
  EvalOp. simpl. apply eval_compare_null_trans; auto.
Qed.

Remark eval_swap_compare_null_trans:
  forall c x v,
  (if Int.eq x Int.zero then Cminor.eval_compare_mismatch c else None) = Some v ->
  match eval_compare_null (swap_comparison c) x with
  | Some true => Some Vtrue
  | Some false => Some Vfalse
  | None => None (A:=val)
  end = Some v.
Proof.
  unfold Cminor.eval_compare_mismatch, eval_compare_null; intros.
  destruct (Int.eq x Int.zero); try discriminate. 
  destruct c; simpl; try discriminate; auto.
Qed.

Theorem eval_comp_int_ptr:
  forall le c a x b y1 y2 v,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vptr y1 y2) ->
  (if Int.eq x Int.zero then Cminor.eval_compare_mismatch c else None) = Some v ->
  eval_expr ge sp e m le (comp c a b) v.
Proof.
  intros until v.
  unfold comp; case (comp_match a b); intros; InvEval.
  EvalOp. simpl. apply eval_swap_compare_null_trans; auto. 
  EvalOp. simpl. rewrite H. apply eval_swap_compare_null_trans; auto. 
  EvalOp. simpl. apply eval_compare_null_trans; auto.
Qed.

Theorem eval_comp_ptr_ptr:
  forall le c a x1 x2 b y1 y2,
  eval_expr ge sp e m le a (Vptr x1 x2) ->
  eval_expr ge sp e m le b (Vptr y1 y2) ->
  x1 = y1 ->
  eval_expr ge sp e m le (comp c a b) (Val.of_bool(Int.cmp c x2 y2)).
Proof.
  intros until y2.
  unfold comp; case (comp_match a b); intros; InvEval.
  EvalOp. simpl. subst y1. rewrite dec_eq_true. 
  destruct (Int.cmp c x2 y2); reflexivity.
Qed.

Theorem eval_comp_ptr_ptr_2:
  forall le c a x1 x2 b y1 y2 v,
  eval_expr ge sp e m le a (Vptr x1 x2) ->
  eval_expr ge sp e m le b (Vptr y1 y2) ->
  x1 <> y1 ->
  Cminor.eval_compare_mismatch c = Some v ->
  eval_expr ge sp e m le (comp c a b) v.
Proof.
  intros until y2.
  unfold comp; case (comp_match a b); intros; InvEval.
  EvalOp. simpl. rewrite dec_eq_false; auto.
  destruct c; simpl in H2; inv H2; auto.
Qed.


Theorem eval_compu:
  forall le c a x b y,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le b (Vint y) ->
  eval_expr ge sp e m le (compu c a b) (Val.of_bool(Int.cmpu c x y)).
Proof.
  intros until y.
  unfold compu; case (comp_match a b); intros; InvEval.
  EvalOp. simpl. rewrite Int.swap_cmpu. destruct (Int.cmpu c x y); reflexivity.
  EvalOp. simpl. destruct (Int.cmpu c x y); reflexivity.
  EvalOp. simpl. rewrite H. rewrite Int.swap_cmpu. destruct (Int.cmpu c x y); reflexivity.
  EvalOp. simpl. rewrite H0. destruct (Int.cmpu c x y); reflexivity.
  EvalOp. simpl. destruct (Int.cmpu c x y); reflexivity.
Qed.

Theorem eval_compf:
  forall le c a x b y,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le b (Vfloat y) ->
  eval_expr ge sp e m le (compf c a b) (Val.of_bool(Float.cmp c x y)).
Proof.
  intros. unfold compf. EvalOp. simpl. 
  destruct (Float.cmp c x y); reflexivity.
Qed.

Theorem eval_negint:
  forall le a x,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le (negint a) (Vint (Int.neg x)).
Proof. intros; unfold negint; EvalOp. Qed.

Theorem eval_negf:
  forall le a x,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le (negf a) (Vfloat (Float.neg x)).
Proof. intros; unfold negf; EvalOp. Qed.

Theorem eval_absf:
  forall le a x,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le (absf a) (Vfloat (Float.abs x)).
Proof. intros; unfold absf; EvalOp. Qed.

Theorem eval_intoffloat:
  forall le a x,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le (intoffloat a) (Vint (Float.intoffloat x)).
Proof. intros; unfold intoffloat; EvalOp. Qed.

Theorem eval_intuoffloat:
  forall le a x,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le (intuoffloat a) (Vint (Float.intuoffloat x)).
Proof. intros; unfold intuoffloat; EvalOp. Qed.

Theorem eval_floatofint:
  forall le a x,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le (floatofint a) (Vfloat (Float.floatofint x)).
Proof. intros; unfold floatofint; EvalOp. Qed.

Theorem eval_floatofintu:
  forall le a x,
  eval_expr ge sp e m le a (Vint x) ->
  eval_expr ge sp e m le (floatofintu a) (Vfloat (Float.floatofintu x)).
Proof. intros; unfold floatofintu; EvalOp. Qed.

Theorem eval_addf:
  forall le a x b y,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le b (Vfloat y) ->
  eval_expr ge sp e m le (addf a b) (Vfloat (Float.add x y)).
Proof. intros; unfold addf; EvalOp. Qed.

Theorem eval_subf:
  forall le a x b y,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le b (Vfloat y) ->
  eval_expr ge sp e m le (subf a b) (Vfloat (Float.sub x y)).
Proof. intros; unfold subf; EvalOp. Qed.

Theorem eval_mulf:
  forall le a x b y,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le b (Vfloat y) ->
  eval_expr ge sp e m le (mulf a b) (Vfloat (Float.mul x y)).
Proof. intros; unfold mulf; EvalOp. Qed.

Theorem eval_divf:
  forall le a x b y,
  eval_expr ge sp e m le a (Vfloat x) ->
  eval_expr ge sp e m le b (Vfloat y) ->
  eval_expr ge sp e m le (divf a b) (Vfloat (Float.div x y)).
Proof. intros; unfold divf; EvalOp. Qed.

Lemma eval_addressing:
  forall le chunk a v b ofs,
  eval_expr ge sp e m le a v ->
  v = Vptr b ofs ->
  match addressing chunk a with (mode, args) =>
    exists vl,
    eval_exprlist ge sp e m le args vl /\ 
    eval_addressing ge sp mode vl = Some v
  end.
Proof.
  intros until v. unfold addressing; case (addressing_match a); intros; InvEval.
  exists (@nil val). split. eauto with evalexpr. simpl. auto.
  exists (Vptr b0 i :: nil). split. eauto with evalexpr. 
    simpl. congruence.
  destruct (is_float_addressing chunk).
  exists (Vptr b0 ofs :: nil).
    split. constructor. econstructor. eauto with evalexpr. simpl. congruence. constructor. 
    simpl. rewrite Int.add_zero. congruence.
  exists (Vptr b0 i :: Vint i0 :: nil).
    split. eauto with evalexpr. simpl. congruence.
  destruct (is_float_addressing chunk).
  exists (Vptr b0 ofs :: nil).
    split. constructor. econstructor. eauto with evalexpr. simpl. congruence. constructor. 
    simpl. rewrite Int.add_zero. congruence.
  exists (Vint i :: Vptr b0 i0 :: nil).
    split. eauto with evalexpr. simpl. 
    rewrite Int.add_commut. congruence.
  destruct (is_float_addressing chunk).
  exists (Vptr b0 ofs :: nil).
    split. constructor. econstructor. eauto with evalexpr. simpl. congruence. constructor. 
    simpl. rewrite Int.add_zero. congruence.
  exists (Vptr b0 i :: Vint i0 :: nil).
    split. eauto with evalexpr. simpl. congruence.
  exists (v :: nil). split. eauto with evalexpr. 
    subst v. simpl. rewrite Int.add_zero. auto.
Qed.

End CMCONSTR.
