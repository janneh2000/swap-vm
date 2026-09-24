# FOURTH_CAMPAIGN_POST_FIX_MAP

Phase 3. For each fix that the audits produced, we record: (a) what the fix *is* in the
eligible-release code, (b) the **assumption the fix now rests on**, and (c) whether that
assumption can be violated from a reachable actor. This is "attack the fix, not the bug."

---

## F-1 — PeggedSwap axis mismatch (OZ C-3) and solve() precision (OZ C-1)

- **Fix in code:** `PeggedSwapMath` computes in a canonical `lt/gt` (address-sorted) frame;
  `solve()` rounding is directed so the pool invariant `C = √(x/X₀)+√(y/Y₀)+A(x/X₀+y/Y₀)`
  is non-decreasing.
- **Assumption the fix rests on:** rounding direction holds for *all* parameterizations,
  including near-zero linear width `A` (the unstable region), asymmetric anchors, reverse
  swap direction, and decimal/rate asymmetry between the two tokens.
- **Attack on the assumption:** AdvPeggedInvariant measures C in the fixed lt/gt frame
  before/after real Aqua swaps across `A∈[0,5000e27]` (incl. 0), asymmetric balances,
  both directions, and rate multipliers {1, 1e12}. **C never decreased** beyond a
  1e-18-relative wei tolerance. Assumption holds. → KILL K4-01.

## F-2 — XYCConcentrate incorrect balances under fee (OZ H-1) + shared-liquidity (OZ C-2)

- **Fix in code:** deployed path is **2D only** (`_xycConcentrateGrowLiquidity2D`); L is
  recomputed from *real* balances each swap; multi-token shared tracking removed from the
  deployed opcode set.
- **Assumption:** recomputing L from real balances after a fee has changed those balances
  still yields register==real settlement and a non-shrinking L.
- **Attack:** AdvCanonicalFull runs `[aquaProtocolFee][concentrate][xycSwap]` — fee mutates
  tokenIn balance *before* concentrate recomputes L — and asserts virtual==real for both
  tokens, global conservation, and no round-trip profit across 3000 fuzz runs. Holds.
  → KILL K4-02.

## F-3 — Hook token injection past price bounds (OZ M-8)

- **Fix in code:** documentation change (maker-facing warning). No code guard added because
  the injection is *maker-authorized* via the maker's own hook.
- **Assumption the residual rests on:** the injection can only be triggered by the maker (or
  the maker's chosen hook), and a *taker* who injects tokenOut mid-callback only harms
  themselves.
- **Attack on the assumption (the real fourth-campaign target):** AdvConcentrateHook has a
  malicious taker call `Aqua.push` in `preTransferOutCallback` to inflate the maker's tokenOut
  balance and bypass the sufficiency check, then reverses to try to bank profit. Result:
  the pushed tokens are *credited to the maker* and the taker cannot recover them — pure
  taker loss; **no round-trip profit** at any fuzzed scale. The "bypass" enriches the pool,
  not the attacker. Assumption holds even under adversarial taker. → KILL K4-03.

## F-4 — Protocol fee pulled before taker transfer (OZ M-9) → v1.0.2 best-effort collection

- **Fix in code (the v1.0.2 change):** `Fee._tryPullFee` wraps the protocol-fee pull in
  try/catch; on failure it emits `ProtocolFeeSkipped` and does **not** credit
  `amountNetPulled` for the un-pulled fee. This is the *only* functional delta of v1.0.2 and
  the sole subject of the differential audits.
- **Assumption:** skipping the fee never desynchronizes `amountNetPulled` from tokens actually
  moved, so the downstream sufficiency check `balanceIn >= original + amountIn − amountNetPulled`
  (SwapVM.sol:240) stays exact.
- **Attack:** AdvSkipConc forces fee-skip conditions and asserts conservation; AdvCanonicalFull
  fuzzes fee bps 0..50% incl. skip regimes. `amountNetPulled` is credited only for landed
  pulls; sufficiency stays exact; taker/maker never lose value to the skip. Only the *protocol*
  can lose fee revenue (the accepted Low). → KILL K4-04.

## F-5 — Decay stores pre-fee amountIn (OZ M-7)

- **Fix in code:** Decay records the correct amountIn relative to its position in the program.
- **Assumption:** ordering fee-before-decay vs decay-before-fee both conserve.
- **Attack:** AdvFeeDecay fuzzes both orderings `[fee][decay][xyc]` and `[decay][fee][xyc]`,
  plus a second time-warped swap with decay state active. Conservation holds both ways. → KILL K4-05.

## F-6 — Multiple Fee fee-on-fee (OZ M-10) & double payment (M-4)

- **Fix in code:** each Fee instance charges on its own `amountIn` snapshot; fee credited once.
- **Assumption:** stacking Fee instructions composes additively without double-charging the
  sufficiency accounting.
- **Attack:** AdvFeeStack stacks fees and checks conservation. Holds. → KILL K4-06.

## F-7 — Calldata.slice underflow (OZ M-3)

- **Fix in code:** `slice` takes an error selector and reverts on out-of-range rather than
  underflowing.
- **Assumption:** every instruction's arg parse uses the guarded slice.
- **Attack:** AdvBoundary / builder round-trips exercise short/edge args; every mis-sized arg
  reverts cleanly. Read-confirmed across all instruction ArgsBuilders. → KILL K4-07.

---

## Assumptions that CANNOT be violated from a reachable actor (summary)

| Fix | Load-bearing assumption | Reachable violation found? |
|-----|-------------------------|----------------------------|
| F-1 | rounding favors maker ∀ params | No |
| F-2 | L recompute from real balances is conservative | No |
| F-3 | taker injection = self-harm only | No |
| F-4 | fee-skip keeps amountNetPulled exact | No |
| F-5 | fee/decay ordering conserves | No |
| F-6 | fee stacking is additive & single-count | No |
| F-7 | guarded slice on all arg parses | No |

Every fix's load-bearing assumption survived direct attack. The residual open surface is
**maker self-harm** and **protocol fee-revenue loss** — neither is counterparty theft.
