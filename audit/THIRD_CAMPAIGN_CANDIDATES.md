# THIRD CAMPAIGN CANDIDATES (grounded in the real audit archive)

Obtained the full 1inch/1inch-audits archive (8 firms v1 + 5 firms v1.0.2). Attacked each fixed
Critical/High's fix-assumption on the eligible code with Foundry. No surviving candidate.

New empirical evidence this campaign:
- C3-A: PeggedSwap invariant-C preservation (attacks the fixes for OZ Critical-1 precision-loss and
  Critical-3 axis-mismatch — the exact quantity that broke was C decreasing = maker loss). Measured C in a
  fixed lt/gt frame before/after real Aqua swaps; C never materially decreases across 4×5000 fuzz runs
  (near-zero A, asymmetric anchors, reverse direction, rate/decimal asymmetry). Fixes HOLD.
  PoC: FINAL_POC/AdvPeggedInvariant.t.sol.
- C3-B: XYCConcentrate hook-injection (OZ Medium "Hook Token Injection", fix = docs for MAKERS only; but
  the injection vector is the TAKER's preTransferOutCallback). On the stateless v1.0.2 concentrate,
  over-extraction via taker injection is pure taker LOSS (paid 500e18 A + injected 100e18 B, received
  49,999 wei B); round-trip fuzz 4000 runs never gains both tokens. The audit's state-corruption impact
  was removed by making concentrate stateless. KILLED. PoC: FINAL_POC/AdvConcentrateHook.t.sol.
- C3-C: dev CoreInvariants suite on untested Aqua-mode compositions (Pegged, Pegged+Decay, Pegged+Fee) —
  all PASS. PoC: FINAL_POC/AdvInvariantsAqua.t.sol.

No candidate promoted. All prior kills stand.
