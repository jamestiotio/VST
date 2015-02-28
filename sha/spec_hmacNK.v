Require Import floyd.proofauto.
Import ListNotations.
Local Open Scope logic.

Require Import sha.spec_sha.
Require Import sha_lemmas.
Require Import sha.HMAC_functional_prog.

(*when generating hmac091c.v using clightgen, manually hack the generated 
file hmac091c.v by adding

Require Import sha.sha.
Definition t_struct_SHA256state_st := sha.t_struct_SHA256state_st.
Definition _key : ident := 141%positive.

BEFORE the definition of all identifiers, and modifying

Definition _key : ident := 41%positive. into
Definition _key : ident := 141%positive.

to avoid a name clash between _key and sha._K256 *)

Require Import sha.hmac_NK.

Record TREP := mkTrep { t: type; v: reptype t}.
Definition tp_of (T:TREP) : type.
  destruct T. apply t0. 
Defined.
Definition v_of (T:TREP) : reptype (tp_of T).
  destruct T. apply v0. 
Defined.

Definition memcpy_spec_data_at :=
  DECLARE _memcpy
   WITH sh : share*share, p: val, q: val, T:TREP
   PRE [ 1%positive OF tptr tvoid, 2%positive OF tptr tvoid, 3%positive OF tuint ]
       PROP (writable_share (snd sh); 0 <= sizeof  (tp_of T) <= Int.max_unsigned)
       LOCAL (`(eq p) (eval_id 1%positive); `(eq q) (eval_id 2%positive);
                    `(eq (Vint (Int.repr (sizeof (tp_of T))))) (eval_id 3%positive))
       SEP (`(data_at (fst sh)  (tp_of T) (v_of T) q);
              `(memory_block (snd sh) (Int.repr (sizeof  (tp_of T))) p))
    POST [ tptr tvoid ]
         local (`(eq p) retval) &&
       (`(data_at (snd sh) (tp_of T) (v_of T) p) *`(data_at (fst sh) (tp_of T) (v_of T) q)).

Inductive hmacabs :=  (* HMAC abstract state *)
 HMACabs: forall (ctx iSha oSha: s256abs) (*sha structures for md_ctx, i_ctx, o_ctx*), 
                 hmacabs.

Definition absCtxt (h:hmacabs): s256abs :=
  match h with HMACabs ctx _ _ => ctx end.

Definition innerShaInit (k: list byte) (s:s256abs):Prop :=
  update_abs (HP.HMAC_SHA256.mkArgZ k HP.Ipad) init_s256abs s.
Definition outerShaInit (k: list byte) (s:s256abs):Prop :=
  update_abs (HP.HMAC_SHA256.mkArgZ k HP.Opad) init_s256abs s.

Definition hmacInit (k:list Z) (h:hmacabs):Prop :=  
  let key := HP.HMAC_SHA256.mkKey k in
  let keyB := map Byte.repr key in
  exists iS oS, innerShaInit keyB iS /\ outerShaInit keyB oS /\
  h = HMACabs iS iS oS.

Definition hmacUpdate (data: list Z) (h1 h2:hmacabs):Prop :=
  match h1 with
    HMACabs ctx1 iS oS
  => exists ctx2, update_abs data ctx1 ctx2
     /\ h2 = HMACabs ctx2 iS oS
  end.

Definition hmacFinalSimple h (digest: list Z) :=
  match h with
    HMACabs ctx iS oS
  => exists oS1, 
       update_abs (sha_finish ctx) oS oS1 /\
       sha_finish oS1 = digest
  end.
(*copying oS to ctx is not modelled here*)

Definition hmacFinal h (digest: list Z) h2 :=
  match h with
    HMACabs ctx iS oS
  => let buf := sha_finish ctx in
     exists oS1, update_abs buf oS oS1 /\
       h2 = HMACabs oS1 iS oS /\
       sha_finish oS1 = digest
  end.
(*copying oS to ctx is modelled here by h2, but it's slightly out of order:
  it "follows" the update buf oS oS1 in order to capture the fact that
   oCtx position is not overwritten.
  Also, the effect of the final sha_final is not captured.*)

(*hmac cleanup not modelled*)

Definition hmacSimple (k:list Z) (data:list Z) (dig:list Z) :=
  exists hInit hUpd,
  hmacInit k hInit /\
  hmacUpdate data hInit hUpd /\
  hmacFinalSimple hUpd dig.

Lemma hmacSimple_sound k data dig: 
      hmacSimple k data dig ->
      dig = HP.HMAC256 data k.
Proof.
 unfold hmacSimple; intros [hInit [hUpd [HH1 [HH2 HH3]]]].
 unfold hmacInit in HH1. destruct HH1 as [iInit [oInit [HiInit [HoInit HINIT]]]]. subst.
 unfold innerShaInit in HiInit. inversion HiInit; clear HiInit.
   rewrite Zlength_correct in *; simpl in *. subst.
 unfold outerShaInit in HoInit. inversion HoInit; clear HoInit.
   rewrite Zlength_correct in *; simpl in *. subst.
 unfold HP.HMAC_SHA256.mkArgZ in *.
 destruct HH2 as [ctx2 [Hupd HU]]. subst.
 inversion Hupd; clear Hupd. subst.
 unfold hmacFinalSimple in HH3. destruct HH3 as [oS [Upd FINISH]]. subst.
 inversion Upd; clear Upd. subst.
 unfold HP.HMAC256, HP.HMAC_SHA256.HMAC, HP.HMAC_SHA256.HmacCore, HP.HMAC_SHA256.KeyPreparation, HP.HMAC_SHA256.OUTER, HP.HMAC_SHA256.INNER.
 unfold sha_finish, HP.SHA256.Hash. rewrite functional_prog.SHA_256'_eq. f_equal.
 unfold HP.HMAC_SHA256.innerArg, HP.HMAC_SHA256.mkArgZ. rewrite H7. clear H7. 
 unfold HP.HMAC_SHA256.outerArg, HP.HMAC_SHA256.mkArgZ. rewrite H12. clear H12.
 unfold sha_finish in *. rewrite intlist_to_Zlist_app in *.
rewrite <- app_assoc. rewrite <- H22; clear H22. 
repeat rewrite <- app_assoc. rewrite H17. reflexivity. 
Qed.

Definition hmac (k:list Z) (data:list Z) (dig:list Z) h :=
  exists hInit hUpd,
  hmacInit k hInit /\
  hmacUpdate data hInit hUpd /\
  hmacFinal hUpd dig h.

Definition hmacFinal_hmacFinalSimple h digest:
  hmacFinalSimple h digest = exists h', hmacFinal h digest h'.
Proof. destruct h. simpl. apply prop_ext.
  split; intros. 
    destruct H as [oS1 [UPD FIN]].
    eexists; exists oS1; eauto.
  destruct H as [h' [oS1 [UPD [H' FIN]]]].
    exists oS1; eauto.
Qed.

Lemma hmac_hmacSimple (k:list Z) (data:list Z) (dig:list Z) :
  hmacSimple k data dig = exists h, hmac k data dig h .
Proof. intros. unfold hmacSimple, hmac.
  apply prop_ext. split; intros.
    destruct H as [hInit [hUpd [HInit [HUpd HFinalSimple]]]].
    rewrite hmacFinal_hmacFinalSimple in HFinalSimple.
    destruct HFinalSimple as [h' H'].
    exists h', hInit, hUpd; auto.
  destruct H as [h' [hInit [hUpd [HInit [HUpd HFinal]]]]].
    exists hInit, hUpd. split; trivial. split; trivial.
    rewrite hmacFinal_hmacFinalSimple. exists h'; trivial.
Qed.

Lemma hmac_sound k data dig h: 
      hmac k data dig h ->
      dig = HP.HMAC256 data k.
Proof.
 intros.
 eapply hmacSimple_sound.
 rewrite hmac_hmacSimple. exists h; eassumption. 
Qed.

Definition hmacstate: Type := 
  (s256state * (s256state * s256state))%type.

Definition mdCtx (h: hmacstate): s256state.
Proof. 
  destruct h as [MDCTX _]. apply MDCTX. 
Defined.

Definition iCtx (h: hmacstate): s256state.
destruct h as [_ [ICTX _]]. apply ICTX.
Defined.

Definition oCtx (h: hmacstate): s256state.
destruct h as [_ [_ OCTX]]. apply OCTX. 
Defined.

Definition hmac_relate (h: hmacabs) (r: hmacstate) : Prop :=
  match h with HMACabs ctx iS oS =>
    s256_relate ctx (mdCtx r) /\
    s256_relate iS (iCtx r) /\
    s256_relate oS (oCtx r) /\
    s256a_len iS = 512 /\ s256a_len oS = 512
  end.

Definition hmacstate_ (h: hmacabs) (c: val) : mpred :=
   EX r:hmacstate, 
    !!  hmac_relate h r && data_at Tsh t_struct_hmac_ctx_st r c.

Definition has_lengthK (l:Z) (key:list Z) :=
  l = Zlength key /\ 0 <= l <= Int.max_signed /\
  l * 8 < two_p 64.

Definition hmac_relate_PreInitNull (key:list Z) (h:hmacabs ) (r: hmacstate) : Prop :=
  match h with HMACabs ctx iS oS =>
    (*no clause for ctx*)
    s256_relate iS (iCtx r) /\
    s256_relate oS (oCtx r) /\
    s256a_len iS = 512 /\ s256a_len oS = 512 /\ 
    let keyB := map Byte.repr (HP.HMAC_SHA256.mkKey key) in
    innerShaInit keyB iS /\ outerShaInit keyB oS
  end.

Definition hmacstate_PreInitNull key (h: hmacabs) (c: val) : mpred :=
   EX r:hmacstate, EX v:_,
    !!  hmac_relate_PreInitNull key h r && 

    data_at Tsh t_struct_hmac_ctx_st 
       (upd_reptype t_struct_hmac_ctx_st [StructField _md_ctx] r v) c.

Definition initPre (c:val) (k: val) h key : mpred:=
  match k with
    Vint z => if Int.eq z Int.zero
              then hmacstate_PreInitNull key h c
              else FF
  | Vptr b ofs => ((data_at_ Tsh t_struct_hmac_ctx_st c) *
                        (data_block Tsh key (Vptr b ofs)))
  | _ => FF
  end.

Definition initPostKey k key:mpred :=
  match k with
    Vint z => !!(z=Int.zero) && emp
  | Vptr b ofs => data_block Tsh key k
  | _ => FF
  end.

Definition HMAC_Init_spec :=
  DECLARE _HMAC_Init
   WITH c : val, k:val, l:Z, key:list Z, KV:val, h1:hmacabs
   PRE [ _ctx OF tptr t_struct_hmac_ctx_st,
         _key OF tptr tuchar,
         _len OF tint ]
         PROP (has_lengthK l key)
         LOCAL (`(eq c) (eval_id _ctx);
                `(eq k) (eval_id _key);
                `(eq (Vint (Int.repr l))) (eval_id _len);
                `(eq KV) (eval_var sha._K256 (tarray tuint 64)))
         SEP (`(K_vector KV); `(initPre c k h1 key))
  POST [ tvoid ] 
           `(EX h:hmacabs, !!hmacInit key h &&
                             (hmacstate_ h c) * 
                             (initPostKey k key) * (K_vector KV)).

Definition has_lengthD (k l:Z) (data:list Z) :=
            l = Zlength data /\ 0 <= l <= Int.max_unsigned /\
            l * 8 + k < two_p 64.

Definition HMAC_Update_spec :=
  DECLARE _HMAC_Update
   WITH h1: hmacabs, c : val, d:val, len:Z, data:list Z, KV:val
   PRE [ (*WAS:_ctx OF tptr t_struct_hmac_ctx_st,
         _data OF tptr tuchar,
         _len OF tint*)
         _ctx OF tptr t_struct_hmac_ctx_st, 
         _data OF tptr tvoid, 
         _len OF tuint]
         PROP (has_lengthD (s256a_len (absCtxt h1)) len data) 
         LOCAL (`(eq c) (eval_id _ctx);
                `(eq d) (eval_id _data);
                `(eq (Vint (Int.repr len))) (eval_id _len);
                `(eq KV) (eval_var sha._K256 (tarray tuint 64)))
         SEP(`(K_vector KV);
             `(hmacstate_ h1 c); `(data_block Tsh data d))
  POST [ tvoid ] 
         EX h2:hmacabs, 
          PROP (hmacUpdate data h1 h2) 
          LOCAL ()
          SEP(`(K_vector KV);
              `(hmacstate_ h2 c); `(data_block Tsh data d)).

Definition hmac_relate_PostFinal (h:hmacabs ) (r: hmacstate) : Prop :=
  match h with HMACabs ctx iS oS =>
    (*no clause for ctx*)
    s256_relate iS (iCtx r) /\
    s256_relate oS (oCtx r) /\
    s256a_len iS = 512 /\ s256a_len oS = 512
  end.

Definition hmacstate_PostFinal (h: hmacabs) (c: val) : mpred :=
   EX r:hmacstate, 
    !!  hmac_relate_PostFinal h r && 
    data_at Tsh t_struct_hmac_ctx_st 
       (upd_reptype t_struct_hmac_ctx_st [StructField _md_ctx] r  (default_val t_struct_SHA256state_st)) c.

Definition HMAC_Final_spec :=
  DECLARE _HMAC_Final
   WITH h1: hmacabs, c : val, md:val, shmd: share, KV:val
   PRE [ _ctx OF tptr t_struct_hmac_ctx_st,
         _md OF tptr tuchar ]
       PROP (writable_share shmd) 
         LOCAL (`(eq md) (eval_id _md); 
                `(eq c) (eval_id _ctx);
                `(eq KV) (eval_var sha._K256 (tarray tuint 64)))
         SEP(`(hmacstate_ h1 c);
             `(K_vector KV);
             `(memory_block shmd (Int.repr 32) md))
  POST [ tvoid ] 
         EX digest:list Z, EX h2:hmacabs, 
          PROP (hmacFinal h1 digest h2) 
          LOCAL ()
          SEP(`(K_vector KV);
              `(hmacstate_PostFinal h2 c);
              `(data_block shmd digest md)).

Definition HMAC_Cleanup_spec :=
  DECLARE _HMAC_cleanup
   WITH h: hmacabs, c : val
   PRE [ _ctx OF tptr t_struct_hmac_ctx_st ]
         PROP () 
         LOCAL (`(eq c) (eval_id _ctx))
         SEP(`(hmacstate_PostFinal h c))
  POST [ tvoid ]  
          PROP (size_compatible t_struct_hmac_ctx_st c /\
                align_compatible t_struct_hmac_ctx_st c) 
          LOCAL ()
          SEP(`(data_block Tsh (list_repeat (Z.to_nat(sizeof t_struct_hmac_ctx_st)) 0) c)).

Record DATA := { LEN:Z; CONT: list Z}.

Definition HMAC_spec :=
  DECLARE _HMAC
   WITH keyVal: val, KEY:DATA,
        msgVal: val, MSG:DATA,
        KV:val, shmd: share, md: val
   PRE [ _key OF tptr tuchar,
         _key_len OF tint,
         _d OF tptr tuchar,
         _n OF tint,
         _md OF tptr tuchar ]
         PROP (writable_share shmd; 
               has_lengthK (LEN KEY) (CONT KEY);
               has_lengthD 512 (LEN MSG) (CONT MSG))
         LOCAL (`(eq md) (eval_id _md); 
                `(eq keyVal) (eval_id _key);
                `(eq (Vint (Int.repr (LEN KEY)))) (eval_id _key_len);
                `(eq msgVal) (eval_id _d);
                `(eq (Vint (Int.repr (LEN MSG)))) (eval_id _n);
                `(eq KV) (eval_var sha._K256 (tarray tuint 64)))
         SEP(`(data_block Tsh (CONT KEY) keyVal);
             `(data_block Tsh (CONT MSG) msgVal);
             `(K_vector KV);
             `(memory_block shmd (Int.repr 32) md))
  POST [ tvoid ] 
         EX digest:_,
          PROP (digest = HP.HMAC256 (CONT MSG) (CONT KEY))
          LOCAL ()
          SEP(`(K_vector KV);
              `(data_block shmd digest md);
              `(initPostKey keyVal (CONT KEY) );
              `(data_block Tsh (CONT MSG) msgVal)).

Definition HMAC_Double_spec :=
  DECLARE _HMAC
   WITH keyVal: val, KEY:DATA,
        msgVal: val, MSG:DATA,
        KV:val, shmd: share, md: val
   PRE [ _key OF tptr tuchar,
         _key_len OF tint,
         _d OF tptr tuchar,
         _n OF tint,
         _md OF tptr tuchar ]
         PROP (writable_share shmd; 
               has_lengthK (LEN KEY) (CONT KEY);
               has_lengthD 512 (LEN MSG) (CONT MSG))
         LOCAL (`(eq md) (eval_id _md); 
                `(eq keyVal) (eval_id _key);
                `(eq (Vint (Int.repr (LEN KEY)))) (eval_id _key_len);
                `(eq msgVal) (eval_id _d);
                `(eq (Vint (Int.repr (LEN MSG)))) (eval_id _n);
                `(eq KV) (eval_var sha._K256 (tarray tuint 64)))
         SEP(`(data_block Tsh (CONT KEY) keyVal);
             `(data_block Tsh (CONT MSG) msgVal);
             `(K_vector KV);
             `(memory_block shmd (Int.repr 64) md))
  POST [ tvoid ] 
         EX digest:_, 
          PROP (digest = HP.HMAC256 (CONT MSG) (CONT KEY))
          LOCAL ()
          SEP(`(K_vector KV);
              `(data_block shmd (digest++digest) md);
              `(initPostKey keyVal (CONT KEY) );
              `(data_block Tsh (CONT MSG) msgVal)).

(*Definition SHA256_spec := (_SHA256, snd spec_sha.SHA256_spec). *)
Definition sha256init_spec := (_SHA256_Init, snd SHA256_Init_spec).
Definition sha256update_spec := (_SHA256_Update, snd SHA256_Update_spec).
Definition sha256final_spec := (_SHA256_Final, snd SHA256_Final_spec).
Definition memset_spec := (_memset, snd spec_sha.memset_spec). 
Definition memcpy_spec := (_memcpy, snd spec_sha.memcpy_spec). 

Definition HmacVarSpecs : varspecs := (sha._K256, tarray tuint 64)::nil.

Definition HmacFunSpecs : funspecs := 
  memcpy_spec_data_at(*memcpy_spec*):: memset_spec::
  sha256init_spec::sha256update_spec::sha256final_spec::(*SHA256_spec::*)
  HMAC_Init_spec:: HMAC_Update_spec::HMAC_Cleanup_spec::
  (*HMAC_FinalSimple_spec *) HMAC_Final_spec::
  HMAC_spec ::
  HMAC_Double_spec::nil.


Definition emptySha:s256state := (nil, (Vundef, (Vundef, (nil, Vundef)))).
 
Definition keyedHMS: hmacstate :=
  (emptySha, (emptySha, emptySha)).

Require Import Blist.
Require Import HMAC_equivalence.
Require Import ByteBitRelations.
Require Import HMAC_isPRF.

Lemma key_vector l:
  length (bytesToBits (HP.HMAC_SHA256.mkKey l)) = 
  HMAC_spec.b HMAC_common_defs.c HMAC_common_defs.p.
Proof. rewrite bytesToBits_len, hmac_common_lemmas.mkKey_length; reflexivity. Qed.

Definition mkCont (l:list Z) : HMAC_spec_abstract.Message (fun x => x=bytesToBits l /\ NPeano.divide 8 (length x)).
eapply exist. split. reflexivity. 
rewrite bytesToBits_len. exists (length l). trivial.
Qed.

Definition bitspec KEY MSG :=
  Vector.to_list ( HMAC_spec.HMAC h_v iv_v (HMAC_spec_abstract.wrappedSAP splitAndPad_v)
                      fpad_v opad_v ipad_v
                      (of_list_length _ (key_vector (CONT KEY)))
                      (mkCont (CONT MSG))).

Definition CRYPTO (A : Comp.OracleComp (HMAC_spec_abstract.Message P)
                                       (Bvector.Bvector HMAC_common_defs.c) bool) 
                  (A_wf : DistSem.well_formed_oc A):=
           forall tau eps sig, h_PRF A tau ->
                               h_star_WCR A eps ->
                               dual_h_RKA A sig ->
  isPRF (Comp.Rnd (HMAC_PRF.b HMAC_common_defs.c HMAC_common_defs.p))
    (Comp.Rnd HMAC_common_defs.c)
    (HMAC_PRF.HMAC h_v iv_v (HMAC_spec_abstract.wrappedSAP splitAndPad_v) fpad_v opad_v ipad_v)
    Message_eqdec 
    (EqDec.Bvector_EqDec HMAC_common_defs.c)
    (Rat.ratAdd (Rat.ratAdd tau eps) sig) A.

Definition HMAC_bitspec :=
  DECLARE _HMAC
   WITH keyVal: val, KEY:DATA,
        msgVal: val, MSG:DATA,
        KV:val, shmd: share, md: val
   PRE [ _key OF tptr tuchar,
         _key_len OF tint,
         _d OF tptr tuchar,
         _n OF tint,
         _md OF tptr tuchar ]
         PROP (writable_share shmd; 
               has_lengthK (LEN KEY) (CONT KEY);
               has_lengthD 512 (LEN MSG) (CONT MSG))
         LOCAL (`(eq md) (eval_id _md); 
                `(eq keyVal) (eval_id _key);
                `(eq (Vint (Int.repr (LEN KEY)))) (eval_id _key_len);
                `(eq msgVal) (eval_id _d);
                `(eq (Vint (Int.repr (LEN MSG)))) (eval_id _n);
                `(eq KV) (eval_var sha._K256 (tarray tuint 64)))
         SEP(`(data_block Tsh (CONT KEY) keyVal);
             `(data_block Tsh (CONT MSG) msgVal);
             `(K_vector KV);
             `(memory_block shmd (Int.repr 32) md))
  POST [ tvoid ] 
         EX digest:_,
          PROP (bytesToBits digest = bitspec KEY MSG /\ 
                forall A Awf, CRYPTO A Awf)
          LOCAL ()
          SEP(`(K_vector KV);
              `(data_block shmd digest md);
              `(initPostKey keyVal (CONT KEY) );
              `(data_block Tsh (CONT MSG) msgVal)).
