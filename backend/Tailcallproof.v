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

(** Recognition of tail calls: correctness proof *)

Require Import Coqlib.
Require Import Maps.
Require Import AST.
Require Import Integers.
Require Import Values.
Require Import Mem.
Require Import Op.
Require Import Events.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Registers.
Require Import RTL.
Require Conventions.
Require Import Tailcall.

(** * Syntactic properties of the code transformation *)

(** ** Measuring the number of instructions eliminated *)

(** The [return_measure c pc] function counts the number of instructions
  eliminated by the code transformation, where [pc] is the successor
  of a call turned into a tailcall.  This is the length of the
  move/nop/return sequence recognized by the [is_return] boolean function.
*)

Fixpoint return_measure_rec (n: nat) (c: code) (pc: node)
                            {struct n}: nat :=
  match n with
  | O => O
  | S n' =>
      match c!pc with
      | Some(Inop s) => S(return_measure_rec n' c s)
      | Some(Iop op args dst s) => S(return_measure_rec n' c s)
      | _ => O
      end
  end.

Definition return_measure (c: code) (pc: node) :=
  return_measure_rec niter c pc.

Lemma return_measure_bounds:
  forall f pc, (return_measure f pc <= niter)%nat.
Proof.
  intro f.
  assert (forall n pc, (return_measure_rec n f pc <= n)%nat).
    induction n; intros; simpl.
    omega.
    destruct (f!pc); try omega. 
    destruct i; try omega.
    generalize (IHn n0). omega.
    generalize (IHn n0). omega.
  intros. unfold return_measure. apply H.
Qed.

Remark return_measure_rec_incr:
  forall f n1 n2 pc,
  (n1 <= n2)%nat ->
  (return_measure_rec n1 f pc <= return_measure_rec n2 f pc)%nat.
Proof.
  induction n1; intros; simpl.
  omega.
  destruct n2. omegaContradiction. assert (n1 <= n2)%nat by omega.
  simpl. destruct f!pc; try omega. destruct i; try omega.
  generalize (IHn1 n2 n H0). omega.
  generalize (IHn1 n2 n H0). omega.
Qed.

Lemma is_return_measure_rec:
  forall f n n' pc r,
  is_return n f pc r = true -> (n <= n')%nat ->
  return_measure_rec n f.(fn_code) pc = return_measure_rec n' f.(fn_code) pc.
Proof.
  induction n; simpl; intros.
  congruence.
  destruct n'. omegaContradiction. simpl.
  destruct (fn_code f)!pc; try congruence.
  destruct i; try congruence.
  decEq. apply IHn with r. auto. omega.
  destruct (is_move_operation o l); try congruence.
  destruct (Reg.eq r r1); try congruence.
  decEq. apply IHn with r0. auto. omega.
Qed.

(** ** Relational characterization of the code transformation *)

(** The [is_return_spec] characterizes the instruction sequences
  recognized by the [is_return] boolean function.  *)

Inductive is_return_spec (f:function): node -> reg -> Prop :=
  | is_return_none: forall pc r,
      f.(fn_code)!pc = Some(Ireturn None) ->
      is_return_spec f pc r
  | is_return_some: forall pc r,
      f.(fn_code)!pc = Some(Ireturn (Some r)) ->
      is_return_spec f pc r
  | is_return_nop: forall pc r s,
      f.(fn_code)!pc = Some(Inop s) ->
      is_return_spec f s r ->
      (return_measure f.(fn_code) s < return_measure f.(fn_code) pc)%nat ->
      is_return_spec f pc r
  | is_return_move: forall pc r r' s,
      f.(fn_code)!pc = Some(Iop Omove (r::nil) r' s) ->
      is_return_spec f s r' ->
      (return_measure f.(fn_code) s < return_measure f.(fn_code) pc)%nat ->
     is_return_spec f pc r.

Lemma is_return_charact:
  forall f n pc rret,
  is_return n f pc rret = true -> (n <= niter)%nat ->
  is_return_spec f pc rret.
Proof.
  induction n; intros.
  simpl in H. congruence.
  generalize H. simpl. 
  caseEq ((fn_code f)!pc); try congruence.
  intro i. caseEq i; try congruence.
  intros s; intros. eapply is_return_nop; eauto. eapply IHn; eauto. omega.
  unfold return_measure.
  rewrite <- (is_return_measure_rec f (S n) niter pc rret); auto.
  rewrite <- (is_return_measure_rec f n niter s rret); auto. 
  simpl. rewrite H2. omega. omega.

  intros op args dst s EQ1 EQ2. 
  caseEq (is_move_operation op args); try congruence.
  intros src IMO. destruct (Reg.eq rret src); try congruence.
  subst rret. intro. 
  exploit is_move_operation_correct; eauto. intros [A B]. subst. 
  eapply is_return_move; eauto. eapply IHn; eauto. omega.
  unfold return_measure.
  rewrite <- (is_return_measure_rec f (S n) niter pc src); auto.
  rewrite <- (is_return_measure_rec f n niter s dst); auto. 
  simpl. rewrite EQ2. omega. omega.
 
  intros or EQ1 EQ2. destruct or; intros. 
  assert (r = rret). eapply proj_sumbool_true; eauto. subst r. 
  apply is_return_some; auto.
  apply is_return_none; auto.
Qed.

(** The [transf_instr_spec] predicate relates one instruction in the
  initial code with its possible transformations in the optimized code. *)

Inductive transf_instr_spec (f: function): instruction -> instruction -> Prop :=
  | transf_instr_tailcall: forall sig ros args res s,
      f.(fn_stacksize) = 0 ->
      is_return_spec f s res ->
      transf_instr_spec f (Icall sig ros args res s) (Itailcall sig ros args)
  | transf_instr_default: forall i,
      transf_instr_spec f i i.

Lemma transf_instr_charact:
  forall f pc instr,
  f.(fn_stacksize) = 0 ->
  transf_instr_spec f instr (transf_instr f pc instr).
Proof.
  intros. unfold transf_instr. destruct instr; try constructor.
  caseEq (is_return niter f n r && Conventions.tailcall_is_possible s &&
          opt_typ_eq (sig_res s) (sig_res (fn_sig f))); intros.
  destruct (andb_prop _ _ H0). destruct (andb_prop _ _ H1).
  eapply transf_instr_tailcall; eauto.
  eapply is_return_charact; eauto. 
  constructor.
Qed.

Lemma transf_instr_lookup:
  forall f pc i,
  f.(fn_code)!pc = Some i ->
  exists i',  (transf_function f).(fn_code)!pc = Some i' /\ transf_instr_spec f i i'.
Proof.
  intros. unfold transf_function. destruct (zeq (fn_stacksize f) 0).
  simpl. rewrite PTree.gmap. rewrite H. simpl. 
  exists (transf_instr f pc i); split. auto. apply transf_instr_charact; auto. 
  exists i; split. auto. constructor.
Qed.

(** * Semantic properties of the code transformation *)

(** ** The ``less defined than'' relation between register states *)

(** A call followed by a return without an argument can be turned
  into a tail call.  In this case, the original function returns
  [Vundef], while the transformed function can return any value.
  We account for this situation by using the ``less defined than''
  relation between values and between memory states.  We need to
  extend it pointwise to register states. *)

Definition regset_lessdef (rs rs': regset) : Prop :=
  forall r, Val.lessdef (rs#r) (rs'#r).

Lemma regset_get_list:
  forall rs rs' l,
  regset_lessdef rs rs' -> Val.lessdef_list (rs##l) (rs'##l).
Proof.
  induction l; simpl; intros; constructor; auto.
Qed.

Lemma regset_set:
  forall rs rs' v v' r,
  regset_lessdef rs rs' -> Val.lessdef v v' ->
  regset_lessdef (rs#r <- v) (rs'#r <- v').
Proof.
  intros; red; intros. repeat rewrite PMap.gsspec. destruct (peq r0 r); auto. 
Qed.

Lemma regset_init_regs:
  forall params vl vl',
  Val.lessdef_list vl vl' ->
  regset_lessdef (init_regs vl params) (init_regs vl' params).
Proof.
  induction params; intros.
  simpl. red; intros. rewrite Regmap.gi. constructor.
  simpl. inv H.   red; intros. rewrite Regmap.gi. constructor.
  apply regset_set. auto. auto.
Qed.

(** ** Agreement between the size of a stack block and a function *)

(** To reason over deallocation of empty stack blocks, we need to
  maintain the invariant that the bounds of a stack block
  for function [f] are always [0, f.(fn_stacksize)]. *)

Inductive match_stacksize: function -> block -> mem -> Z -> Prop :=
  | match_stacksize_intro: forall f sp m bound,
      sp < bound ->
      low_bound m sp = 0 ->
      high_bound m sp = f.(fn_stacksize) ->
      match_stacksize f sp m bound.

Lemma match_stacksize_store:
  forall m m' chunk  b ofs v f sp bound,
  store chunk m b ofs v = Some m' ->
  match_stacksize f sp m bound ->
  match_stacksize f sp m' bound.
Proof.
  intros. inv H0. constructor. auto.
  rewrite <- H2. eapply Mem.low_bound_store; eauto.
  rewrite <- H3. eapply Mem.high_bound_store; eauto.
Qed.

Lemma match_stacksize_alloc_other:
  forall m m' lo hi b f sp bound,
  alloc m lo hi = (m', b) ->
  match_stacksize f sp m bound ->
  bound <= m.(nextblock) ->
  match_stacksize f sp m' bound.
Proof.
  intros. inv H0.
  assert (valid_block m sp). red. omega.
  constructor. auto.
  rewrite <- H3. eapply low_bound_alloc_other; eauto.
  rewrite <- H4. eapply high_bound_alloc_other; eauto.
Qed.

Lemma match_stacksize_alloc_same:
  forall m f m' sp,
  alloc m 0 f.(fn_stacksize) = (m', sp) ->
  match_stacksize f sp m' m'.(nextblock).
Proof.
  intros. constructor. 
  unfold alloc in H. inv H. simpl. omega.
  eapply low_bound_alloc_same; eauto.
  eapply high_bound_alloc_same; eauto.
Qed.

Lemma match_stacksize_free:
  forall f sp m b bound,
  match_stacksize f sp m bound ->
  bound <= b ->
  match_stacksize f sp (free m b) bound.
Proof.
  intros. inv H. constructor. auto.
  rewrite <- H2. apply low_bound_free. unfold block; omega.
  rewrite <- H3. apply high_bound_free. unfold block; omega.
Qed.

(** * Proof of semantic preservation *)

Section PRESERVATION.

Variable prog: program.
Let tprog := transf_program prog.
Let ge := Genv.globalenv prog.
Let tge := Genv.globalenv tprog.

Lemma symbols_preserved:
  forall (s: ident), Genv.find_symbol tge s = Genv.find_symbol ge s.
Proof (Genv.find_symbol_transf transf_fundef prog).

Lemma functions_translated:
  forall (v: val) (f: RTL.fundef),
  Genv.find_funct ge v = Some f ->
  Genv.find_funct tge v = Some (transf_fundef f).
Proof (@Genv.find_funct_transf _ _ _ transf_fundef prog).

Lemma funct_ptr_translated:
  forall (b: block) (f: RTL.fundef),
  Genv.find_funct_ptr ge b = Some f ->
  Genv.find_funct_ptr tge b = Some (transf_fundef f).
Proof (@Genv.find_funct_ptr_transf _ _ _ transf_fundef prog).

Lemma sig_preserved:
  forall f, funsig (transf_fundef f) = funsig f.
Proof.
  destruct f; auto. simpl. unfold transf_function. 
  destruct (zeq (fn_stacksize f) 0); auto. 
Qed.

Lemma find_function_translated:
  forall ros rs rs' f,
  find_function ge ros rs = Some f ->
  regset_lessdef rs rs' ->
  find_function tge ros rs' = Some (transf_fundef f).
Proof.
  intros until f; destruct ros; simpl.
  intros.
  assert (rs'#r = rs#r).
    exploit Genv.find_funct_inv; eauto. intros [b EQ].
    generalize (H0 r). rewrite EQ. intro LD. inv LD. auto.
  rewrite H1. apply functions_translated; auto.
  rewrite symbols_preserved. destruct (Genv.find_symbol ge i); intros.
  apply funct_ptr_translated; auto.
  discriminate.
Qed.

(** Consider an execution of a call/move/nop/return sequence in the
  original code and the corresponding tailcall in the transformed code.
  The transition sequences are of the following form
  (left: original code, right: transformed code).
  [f] is the calling function and [fd] the called function.
<<
     State stk f (Icall instruction)       State stk' f' (Itailcall)

     Callstate (frame::stk) fd args        Callstate stk' fd' args'
            .                                       .
            .                                       .
            .                                       .
     Returnstate (frame::stk) res          Returnstate stk' res'

     State stk f (move/nop/return seq)
            .
            .
            .
     State stk f (return instr)

     Returnstate stk res
>>
The simulation invariant must therefore account for two kinds of
mismatches between the transition sequences:
- The call stack of the original program can contain more frames
  than that of the transformed program (e.g. [frame] in the example above).
- The regular states corresponding to executing the move/nop/return
  sequence must all correspond to the single [Returnstate stk' res']
  state of the transformed program.

We first define the simulation invariant between call stacks.
The first two cases are standard, but the third case corresponds
to a frame that was eliminated by the transformation. *)

Inductive match_stackframes: mem -> Z -> list stackframe -> list stackframe -> Prop :=
  | match_stackframes_nil: forall m bound,
      match_stackframes m bound nil nil
  | match_stackframes_normal: forall m bound stk stk' res sp pc rs rs' f,
      match_stackframes m sp stk stk' ->
      match_stacksize f sp m bound ->
      regset_lessdef rs rs' ->
      match_stackframes m bound
        (Stackframe res f.(fn_code) (Vptr sp Int.zero) pc rs :: stk)
        (Stackframe res (transf_function f).(fn_code) (Vptr sp Int.zero) pc rs' :: stk')
  | match_stackframes_tail: forall m bound stk stk' res sp pc rs f,
      match_stackframes m sp stk stk' ->
      match_stacksize f sp m bound ->
      is_return_spec f pc res ->
      f.(fn_stacksize) = 0 ->
      match_stackframes m bound
        (Stackframe res f.(fn_code) (Vptr sp Int.zero) pc rs :: stk)
        stk'.

(** In [match_stackframes m bound s s'], the memory state [m] is used
  to check that the sizes of the stack blocks agree with what was
  declared by the corresponding functions.  The [bound] parameter
  is used to enforce separation between the stack blocks. *)

Lemma match_stackframes_incr:
  forall m bound s s' bound',
  match_stackframes m bound s s' ->
  bound <= bound' ->
  match_stackframes m bound' s s'.
Proof.
  intros. inv H; econstructor; eauto. 
  inv H2. constructor; auto. omega.
  inv H2. constructor; auto. omega.
Qed.

Lemma match_stackframes_store:
  forall m bound s s',
  match_stackframes m bound s s' -> 
  forall chunk b ofs v m',
  store chunk m b ofs v = Some m' ->
  match_stackframes m' bound s s'.
Proof.
  induction 1; intros.
  constructor.
  econstructor; eauto. eapply match_stacksize_store; eauto.
  econstructor; eauto. eapply match_stacksize_store; eauto.
Qed.

Lemma match_stackframes_alloc:
  forall m lo hi m' sp s s',
  match_stackframes m (nextblock m) s s' ->
  alloc m lo hi = (m', sp) ->
  match_stackframes m' sp s s'.
Proof.
  intros. 
  assert (forall bound s s',
    match_stackframes m bound s s' ->
    bound <= m.(nextblock) ->
    match_stackframes m' bound s s').
  induction 1; intros. constructor.
  constructor; auto. apply IHmatch_stackframes; auto. inv H2. omega. 
  eapply match_stacksize_alloc_other; eauto.
  econstructor; eauto.  apply IHmatch_stackframes; auto. inv H2. omega. 
  eapply match_stacksize_alloc_other; eauto.
  exploit alloc_result; eauto. intro. rewrite H2.
  eapply H1; eauto. omega.
Qed. 

Lemma match_stackframes_free:
  forall f sp m s s',
  match_stacksize f sp m (nextblock m) ->
  match_stackframes m sp s s' ->
  match_stackframes (free m sp) (nextblock (free m sp)) s s'.
Proof.
  intros. simpl. 
  assert (forall bound s s',
    match_stackframes m bound s s' ->
    bound <= sp ->
    match_stackframes (free m sp) bound s s').
  induction 1; intros. constructor.
  constructor; auto. apply IHmatch_stackframes; auto. inv H2; omega. 
  apply match_stacksize_free; auto.
  econstructor; eauto. apply IHmatch_stackframes; auto. inv H2; omega. 
  apply match_stacksize_free; auto.

  apply match_stackframes_incr with sp. apply H1; auto. omega.
  inv H. omega. 
Qed.

(** Here is the invariant relating two states.  The first three
  cases are standard.  Note the ``less defined than'' conditions
  over values, register states, and memory states. *)

Inductive match_states: state -> state -> Prop :=
  | match_states_normal:
      forall s sp pc rs m s' rs' m' f
             (STKSZ: match_stacksize f sp m m.(nextblock))
             (STACKS: match_stackframes m sp s s')
             (RLD: regset_lessdef rs rs')
             (MLD: Mem.lessdef m m'),
      match_states (State s f.(fn_code) (Vptr sp Int.zero) pc rs m)
                   (State s' (transf_function f).(fn_code) (Vptr sp Int.zero) pc rs' m')
  | match_states_call:
      forall s f args m s' args' m',
      match_stackframes m m.(nextblock) s s' ->
      Val.lessdef_list args args' ->
      Mem.lessdef m m' ->
      match_states (Callstate s f args m)
                   (Callstate s' (transf_fundef f) args' m')
  | match_states_return:
      forall s v m s' v' m',
      match_stackframes m m.(nextblock) s s' ->
      Val.lessdef v v' ->
      Mem.lessdef m m' ->
      match_states (Returnstate s v m)
                   (Returnstate s' v' m')
  | match_states_interm:
      forall s sp pc rs m s' m' f r v'
             (STKSZ: match_stacksize f sp m m.(nextblock))
             (STACKS: match_stackframes m sp s s')
             (MLD: Mem.lessdef m m'),
      is_return_spec f pc r ->
      f.(fn_stacksize) = 0 ->
      Val.lessdef (rs#r) v' ->
      match_states (State s f.(fn_code) (Vptr sp Int.zero) pc rs m)
                   (Returnstate s' v' m').

(** The last case of [match_states] corresponds to the execution
  of a move/nop/return sequence in the original code that was
  eliminated by the transformation:
<<
     State stk f (move/nop/return seq)  ~~  Returnstate stk' res'
            .
            .
            .
     State stk f (return instr)         ~~  Returnstate stk' res'
>>
  To preserve non-terminating behaviors, we need to make sure
  that the execution of this sequence in the original code cannot
  diverge.  For this, we introduce the following complicated
  measure over states, which will decrease strictly whenever
  the original code makes a transition but the transformed code
  does not. *)

Definition measure (st: state) : nat :=
  match st with
  | State s c sp pc rs m => (List.length s * (niter + 2) + return_measure c pc + 1)%nat
  | Callstate s f args m => 0%nat
  | Returnstate s v m => (List.length s * (niter + 2))%nat
  end.

Ltac TransfInstr :=
  match goal with
  | H: (PTree.get _ (fn_code _) = _) |- _ =>
      destruct (transf_instr_lookup _ _ _ H) as [i' [TINSTR TSPEC]]; inv TSPEC
  end.

Ltac EliminatedInstr :=
  match goal with
  | H: (is_return_spec _ _ _) |- _ => inv H; try congruence
  | _ => idtac
  end.

(** The proof of semantic preservation, then, is a simulation diagram
  of the ``option'' kind. *)

Lemma transf_step_correct:
  forall s1 t s2, step ge s1 t s2 ->
  forall s1' (MS: match_states s1 s1'),
  (exists s2', step tge s1' t s2' /\ match_states s2 s2')
  \/ (measure s2 < measure s1 /\ t = E0 /\ match_states s2 s1')%nat.
Proof.
  induction 1; intros; inv MS; EliminatedInstr.

(* nop *)
  TransfInstr. left. econstructor; split. 
  eapply exec_Inop; eauto. constructor; auto.
(* eliminated nop *)
  assert (s0 = pc') by congruence. subst s0.
  right. split. simpl. omega. split. auto. 
  econstructor; eauto. 

(* op *)
  TransfInstr.
  assert (Val.lessdef_list (rs##args) (rs'##args)). apply regset_get_list; auto. 
  exploit eval_operation_lessdef; eauto. 
  intros [v' [EVAL' VLD]]. 
  left. exists (State s' (fn_code (transf_function f)) (Vptr sp0 Int.zero) pc' (rs'#res <- v') m'); split.
  eapply exec_Iop; eauto.  rewrite <- EVAL'.
  apply eval_operation_preserved. exact symbols_preserved.
  econstructor; eauto. apply regset_set; auto.
(* eliminated move *)
  rewrite H1 in H. clear H1. inv H. 
  right. split. simpl. omega. split. auto.
  econstructor; eauto. simpl in H0. rewrite PMap.gss. congruence. 

(* load *)
  TransfInstr.
  assert (Val.lessdef_list (rs##args) (rs'##args)). apply regset_get_list; auto. 
  exploit eval_addressing_lessdef; eauto. 
  intros [a' [ADDR' ALD]].
  exploit loadv_lessdef; eauto. 
  intros [v' [LOAD' VLD]].
  left. exists (State s' (fn_code (transf_function f)) (Vptr sp0 Int.zero) pc' (rs'#dst <- v') m'); split.
  eapply exec_Iload; eauto.  rewrite <- ADDR'.
  apply eval_addressing_preserved. exact symbols_preserved.
  econstructor; eauto. apply regset_set; auto.

(* store *)
  TransfInstr.
  assert (Val.lessdef_list (rs##args) (rs'##args)). apply regset_get_list; auto. 
  exploit eval_addressing_lessdef; eauto. 
  intros [a' [ADDR' ALD]].
  exploit storev_lessdef. 4: eexact H1. eauto. eauto. apply RLD.  
  intros [m'1 [STORE' MLD']].
  left. exists (State s' (fn_code (transf_function f)) (Vptr sp0 Int.zero) pc' rs' m'1); split.
  eapply exec_Istore; eauto.  rewrite <- ADDR'.
  apply eval_addressing_preserved. exact symbols_preserved.
  destruct a; simpl in H1; try discriminate.
  econstructor; eauto.
  eapply match_stacksize_store; eauto. 
  rewrite (nextblock_store _ _ _ _ _ _ H1). auto.
  eapply match_stackframes_store; eauto.

(* call *)
  exploit find_function_translated; eauto. intro FIND'.  
  TransfInstr.
(* call turned tailcall *)
  left. exists (Callstate s' (transf_fundef f) (rs'##args) (Mem.free m' sp0)); split.
  eapply exec_Itailcall; eauto. apply sig_preserved. 
  constructor. eapply match_stackframes_tail; eauto. apply regset_get_list; auto.
  apply Mem.free_right_lessdef; auto. inv STKSZ. omega.  
(* call that remains a call *)
  left. exists (Callstate (Stackframe res (fn_code (transf_function f0)) (Vptr sp0 Int.zero) pc' rs' :: s')
                          (transf_fundef f) (rs'##args) m'); split.
  eapply exec_Icall; eauto. apply sig_preserved. 
  constructor. constructor; auto. apply regset_get_list; auto. auto. 

(* tailcall *) 
  exploit find_function_translated; eauto. intro FIND'.  
  TransfInstr.
  left. exists (Callstate s' (transf_fundef f) (rs'##args) (Mem.free m' stk)); split.
  eapply exec_Itailcall; eauto. apply sig_preserved. 
  constructor. eapply match_stackframes_free; eauto. 
  apply regset_get_list; auto. apply Mem.free_lessdef; auto.

(* cond true *)
  TransfInstr. 
  left. exists (State s' (fn_code (transf_function f)) (Vptr sp0 Int.zero) ifso rs' m'); split.
  eapply exec_Icond_true; eauto.
  apply eval_condition_lessdef with (rs##args); auto. apply regset_get_list; auto.
  constructor; auto. 

(* cond false *)
  TransfInstr. 
  left. exists (State s' (fn_code (transf_function f)) (Vptr sp0 Int.zero) ifnot rs' m'); split.
  eapply exec_Icond_false; eauto.
  apply eval_condition_lessdef with (rs##args); auto. apply regset_get_list; auto.
  constructor; auto. 

(* return *)
  TransfInstr.
  left. exists (Returnstate s' (regmap_optget or Vundef rs') (free m' stk)); split.
  apply exec_Ireturn; auto.
  constructor.
  eapply match_stackframes_free; eauto. 
  destruct or; simpl. apply RLD. constructor.
  apply Mem.free_lessdef; auto.

(* eliminated return None *)
  assert (or = None) by congruence. subst or. 
  right. split. simpl. omega. split. auto. 
  constructor.
  eapply match_stackframes_free; eauto.
  simpl. constructor.
  apply Mem.free_left_lessdef; auto. 

(* eliminated return Some *)
  assert (or = Some r) by congruence. subst or.
  right. split. simpl. omega. split. auto.
  constructor.
  eapply match_stackframes_free; eauto.
  simpl. auto.
  apply Mem.free_left_lessdef; auto.

(* internal call *)
  caseEq (alloc m'0 0 (fn_stacksize f)). intros m'1 stk' ALLOC'.
  exploit alloc_lessdef; eauto. intros [EQ1 LD']. subst stk'. 
  assert (fn_stacksize (transf_function f) = fn_stacksize f /\
          fn_entrypoint (transf_function f) = fn_entrypoint f /\
          fn_params (transf_function f) = fn_params f).
    unfold transf_function. destruct (zeq (fn_stacksize f) 0); auto. 
  destruct H0 as [EQ1 [EQ2 EQ3]]. 
  left. econstructor; split.
  simpl. eapply exec_function_internal; eauto. rewrite EQ1; eauto.
  rewrite EQ2. rewrite EQ3. constructor; auto.
  eapply match_stacksize_alloc_same; eauto.
  eapply match_stackframes_alloc; eauto. 
  apply regset_init_regs. auto. 

(* external call *)
  exploit event_match_lessdef; eauto. intros [res' [EVM' VLD']]. 
  left. exists (Returnstate s' res' m'); split.
  simpl. econstructor; eauto.
  constructor; auto. 

(* returnstate *)
  inv H2. 
(* synchronous return in both programs *)
  left. econstructor; split. 
  apply exec_return. 
  constructor; auto. apply regset_set; auto. 
(* return instr in source program, eliminated because of tailcall *)
  right. split. unfold measure. simpl length. 
  change (S (length s) * (niter + 2))%nat
   with ((niter + 2) + (length s) * (niter + 2))%nat. 
  generalize (return_measure_bounds (fn_code f) pc). omega.  
  split. auto. 
  econstructor; eauto.
  rewrite Regmap.gss. auto. 
Qed.

Lemma transf_initial_states:
  forall st1, initial_state prog st1 ->
  exists st2, initial_state tprog st2 /\ match_states st1 st2.
Proof.
  intros. inv H. 
  exploit funct_ptr_translated; eauto. intro FIND.
  exists (Callstate nil (transf_fundef f) nil (Genv.init_mem tprog)); split.
  econstructor; eauto.
  replace (prog_main tprog) with (prog_main prog).
  rewrite symbols_preserved. eauto.
  reflexivity.
  rewrite <- H2. apply sig_preserved.
  replace (Genv.init_mem tprog) with (Genv.init_mem prog).
  constructor. constructor. constructor. apply lessdef_refl. 
  symmetry. unfold tprog, transf_program. apply Genv.init_mem_transf. 
Qed.

Lemma transf_final_states:
  forall st1 st2 r, 
  match_states st1 st2 -> final_state st1 r -> final_state st2 r.
Proof.
  intros. inv H0. inv H. inv H5. inv H3. constructor. 
Qed.


(** The preservation of the observable behavior of the program then
  follows, using the generic preservation theorem
  [Smallstep.simulation_opt_preservation]. *)

Theorem transf_program_correct:
  forall (beh: program_behavior),
  exec_program prog beh -> exec_program tprog beh.
Proof.
  unfold exec_program; intros.
  eapply simulation_opt_preservation with (measure := measure); eauto.
  eexact transf_initial_states.
  eexact transf_final_states.
  exact transf_step_correct. 
Qed.

End PRESERVATION.

