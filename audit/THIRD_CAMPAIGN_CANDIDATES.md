# THIRD CAMPAIGN CANDIDATES

Blocker: audit PDF not present (see AUDIT_ASSUMPTION_ATTACK_MAP.md). Work this campaign used the
whitepapers + code + the repo's own invariant suite applied to the deployed Aqua path.

No new surviving candidate. New evidence gathered:
- Whitepaper documents 7 invariants + canonical ordering + conservation law + no-custody model.
- The repo's rigorous CoreInvariants (symmetry / quote-swap / monotonicity / additivity /
  rounding-favors-maker / balance-sufficiency) were run — for the first time — on the DEPLOYED
  AquaSwapVMRouter + REAL Aqua settlement (the repo's own invariant tests run on SwapVMRouter +
  StaticBalances in signature mode) and on compositions the repo ships NO test for:
    - Pegged (aqua)         -> PASS
    - Pegged + Decay (aqua) -> PASS  (untested combo)
    - Pegged + aquaFee (aqua) -> PASS (untested-in-aqua combo)
  PoC: test/adv/AdvInvariantsAqua.t.sol (mirrored to FINAL_POC/).

Candidates carried from campaign 2 remain KILLED/out-of-model (C2-01 extreme-scale pegged rounding;
C2-02 maker-config anchor mismatch).
