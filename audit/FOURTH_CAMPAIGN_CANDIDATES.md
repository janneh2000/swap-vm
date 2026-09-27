# FOURTH_CAMPAIGN_CANDIDATES

Every hypothesis raised in the fourth campaign, with its status. A candidate is a *specific*
mechanism-level claim of impact, not a vibe. Each is either KILLED (with the PoC/argument that
killed it, cross-ref KILL_LEDGER) or, if it had survived, promoted to a report. **None
survived.**

Format: ID · claim · actor · required-impact · verdict.

---

### C4-01 — Fee-skip desync underpays maker
- **Claim:** v1.0.2 best-effort fee-skip credits `amountNetPulled` for a fee that was not
  pulled, so the sufficiency check `balanceIn >= original + amountIn − amountNetPulled` passes
  with the maker short.
- **Actor:** T. **Impact needed:** maker receives less tokenIn than amountIn while taker keeps tokenOut.
- **Verdict:** KILLED (K4-04). Code: `_tryPullFee` credits `amountNetPulled` only inside the
  successful branch; on catch it emits `ProtocolFeeSkipped` and credits nothing. AdvSkipConc +
  AdvCanonicalFull: conservation exact, maker never short. Only protocol fee revenue can drop.

### C4-02 — Concentrate-after-fee L recompute leaks
- **Claim:** fee mutates tokenIn balance, then concentrate recomputes L on the mutated balance,
  producing a virtual reserve inconsistent with real → drainable.
- **Actor:** T. **Impact needed:** round-trip profit or virtual>real.
- **Verdict:** KILLED (K4-02). AdvCanonicalFull `[aquaProtocolFee][concentrate][xycSwap]`:
  virtual==real both tokens, no round-trip profit, 3000 runs.

### C4-03 — Backward jump double-settles
- **Claim:** a program can `_jump` back onto a curve/fee after amounts are set; the second run
  pushes tokenOut again → double extraction.
- **Actor:** M-program (note: T cannot craft the program — it's hash-bound).
- **Impact needed:** maker's real tokenOut drops by 2×amountOut.
- **Verdict:** KILLED (K4-08). AdvBackwardJump: every value-computing instruction has
  `require(amountIn==0 || amountOut==0)`; the back-jump reverts. Baseline (no jump) settles once.

### C4-04 — Taker push in preTransferOutCallback → over-extract then reverse for profit
- **Claim:** taker inflates maker tokenOut via `Aqua.push` inside the callback to pass the
  sufficiency check for an amountOut larger than the real reserve, then sells back.
- **Actor:** T. **Impact needed:** taker ends up with more of the start token.
- **Verdict:** KILLED (K4-03). AdvConcentrateHook: pushed tokens are credited to the maker's
  balance; the taker cannot pull them back; net taker loss at every fuzzed injection size. The
  sufficiency "bypass" enriches the pool.

### C4-05 — Pegged∘Decay / Pegged∘Fee invariant carry breaks under real Aqua settlement
- **Claim:** the repo tests these invariants only in sig mode / StaticBalances; the real Aqua
  ledger path could diverge.
- **Actor:** T. **Impact needed:** invariant/monotonicity violation → profit.
- **Verdict:** KILLED (K4-09). AdvInvariantsAqua runs the repo's own CoreInvariants
  (symmetry/quote-swap/monotonicity/additivity/rounding-favors-maker/sufficiency) on the
  deployed AquaSwapVMRouter + real Aqua path for Pegged, Pegged∘Decay, Pegged∘Fee. Pass.

### C4-06 — PeggedSwap near-zero A instability re-drains
- **Claim:** the OZ C-1 unstable region (A≈0) still lets C decrease under some direction/rate.
- **Actor:** T. **Impact needed:** C decreases → maker pays out too much.
- **Verdict:** KILLED (K4-01). AdvPeggedInvariant.testFuzz_C_smallA (A∈[0,1e24]) + asymmetric +
  rates: C non-decreasing.

### C4-07 — Extreme-scale round-trip surplus is amplifiable
- **Claim:** the wei-level surplus seen only at >=~1e25 reserves + huge trades can be repeated
  to drain.
- **Actor:** T. **Impact needed:** repeatable net-positive extraction at reachable scale.
- **Verdict:** KILLED (K2-01, re-confirmed). AdvBoundary at realistic (<=1e24) scale: round-trip
  is maker-favorable. The surplus is bounded rounding dust inside OZ's reviewed PeggedSwap
  tolerance and does not amplify; not reachable with real-value pools.

### C4-08 — WETH unwrap without token==WETH guard enables cross-actor loss
- **Claim:** SwapVM.sol:275-278 unwraps tokenOut without checking token==WETH; a mismatch could
  send someone else's funds or brick a maker.
- **Actor:** T (sets shouldUnwrapWeth). **Impact needed:** cross-actor value move.
- **Verdict:** KILLED (K4-10). If tokenOut≠WETH, `IWETH(token).safeWithdrawTo` reverts (no
  `withdraw` on a plain ERC20) → the taker's own tx reverts. Pure self-grief, no counterparty
  impact. Matches OZ Low "will resolve"; no exploit.

### C4-09 — Third-party `Aqua.push`/`ship`/`dock` cross-maker corruption
- **Claim:** externally-callable Aqua funcs let a 3P corrupt or drain a victim maker's balance.
- **Actor:** 3P. **Impact needed:** victim maker balance decreases or aliases.
- **Verdict:** KILLED (K4-11). Balances keyed by `[maker][app][strategyHash][token]`; `push`
  only *credits*; `pull` uses `app==msg.sender`; `ship`/`dock` scoped to caller's own maker key.
  No cross-maker write. See REACHABILITY_MAP / STATE_MODEL.

### C4-10 — Instruction-ordering aliasing (A+B vs B+A vs A+A)
- **Claim:** some ordering of fee/decay/concentrate/swap produces non-conservative settlement.
- **Actor:** T. **Impact needed:** conservation break in some ordering.
- **Verdict:** KILLED (K4-05/K4-06). AdvFeeDecay (both fee/decay orderings), AdvFeeStack (A+A),
  AdvCanonicalFull (full A+B+C). All conserve.

---

## Promotions

**0 candidates promoted to a report.** No mechanism produced counterparty theft, price-bound
escape for profit, double-settlement, invariant decrease at reachable scale, or accounting
drift. Per mission directive, nothing is manufactured into a finding.
