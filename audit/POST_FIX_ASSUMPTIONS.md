# POST-FIX ASSUMPTIONS (Specialist A) — attack the mitigations, not the original bugs

## Fee change (v1.0.2, OZ M-09 / Theori #10): best-effort Aqua protocol fee
- Original invariant: protocol fee on tokenIn is collected from the maker's Aqua inventory during runLoop.
- Mitigation: `_tryPullFee` = try/catch; credit `amountNetPulled` ONLY when the pull lands; else emit
  ProtocolFeeSkipped and leave the maker holding the fee.
- New assumptions created + who relies on them, and the attack + result:
  1. "try/catch is atomic: on failure the balance decrement AND token transfer both roll back."
     Relied on by: the tokenIn sufficiency check in SwapVM._transferIn. ATTACK: force a skip (maker can't
     cover fee) and check settlement. RESULT: PROVEN — AdvSkipConc.testFuzz_feeSkip_conservation (5000 runs):
     taker pays exactly amountIn, feeTo gets 0, maker virtual delta == real delta == amountIn. No divergence.
  2. "amountNetPulled == tokenIn actually removed from the maker ledger."
     Relied on by: the sufficiency check subtracting it. ATTACK: fuzz fee 0..100% × dir × exactIn/Out ×
     ordering × pay-mode × stacked fees. RESULT: PROVEN — AdvConservation (4000×2) + AdvFeeStack (5000):
     exact conservation, register==real, feeTo gets exactly the pulled amount.
  3. "the skip outcome is taker-neutral (only fee-recipient/maker affected)."
     ATTACK: check taker in/out unchanged between collect and skip. RESULT: PROVEN — taker in/out identical.

## PeggedSwap fixes (OZ: invariant-breaking pricing/reserve-loss; exact-out rounding; token-binding)
- Mitigation (as-shipped): maker-favorable rounding (amountOut floor / amountIn ceil; y1 up / x1 up),
  numerical-stability rationalization in PeggedSwapMath.solve, documented bounds (u <= u* <= 4*ONE, x<=1e30).
- New assumptions + attack + result:
  1. "current reserve stays within the documented bound so u = x/x0 stays <= ~4*ONE."
     Relied on by: the no-overflow / rounding-direction guarantees. ATTACK: drive reserves far from the
     config anchor via large trades, Decay inflation, and rate(decimal) asymmetry; round-trip for profit.
     RESULT: PROVEN maker-favorable at realistic scales (<=1e24), 8000 runs (AdvBoundary). A wei-level
     round-trip SURPLUS appears only at absurd reserves (>=~1e25) and does NOT amplify (500 trips @1e24 = net
     loss) — benign rounding, KILLED (K2-01).
  2. "config anchors (x0/y0) equal the shipped reserves (SDK builds them so)."
     ATTACK: ship reserves != config anchors. RESULT: mispricing/round-trip surplus IS reachable, but only
     under maker MISCONFIGURATION (no SDK/sane maker does this); out of the unprivileged-taker model.
     Documented as a maker footgun (NEW_CANDIDATES C2-02), not a protocol vuln.
  3. "Decay (tuned for XYC) composed before PeggedSwap does not create a taker-favorable price."
     ATTACK: Pegged+Decay round-trip with warp. RESULT: PROVEN maker-favorable (AdvFuzz/AdvBoundary).

## Instruction-ordering ("security-critical") — exploited as a property, not documented
- ATTACK: stacked fees, fee↔curve orderings, Decay↔curve, Concentrate↔curve, all via real settlement.
- RESULT: every ordering that a sane program uses conserves value; the only ordering-sensitive losses
  require a maker to author a self-harming program (documented risk), never a taker choice.
