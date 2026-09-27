# FOURTH_CAMPAIGN_KILL_LEDGER

The record of what was tried and *why it does not work*. A kill is only valid with either a
runnable PoC (green = attack failed to produce impact) or a read-confirmed structural
guarantee with the exact code location. Historical kills from campaigns 1–3 are carried
forward by reference; new fourth-campaign kills are K4-xx.

Toolchain: forge (solc 0.8.30, via_ir, optimizer 700), deployed router `AquaSwapVMRouter`
→ `AquaOpcodes`, real `Aqua` ledger. All PoCs in `test/adv/` (mirrored in `audit/FINAL_POC/`).
Full suite result: **15 suites, 34 tests, 0 failed.**

---

| ID | Attack | Kill evidence | Type |
|----|--------|---------------|------|
| K4-01 | PeggedSwap invariant C decreases (OZ C-1/C-3 re-emergence) incl. near-zero A, asymmetric anchors, reverse dir, rate asymmetry | AdvPeggedInvariant (4 tests): C measured in fixed lt/gt frame non-decreasing within 1e-18 rel tol across A∈[0,5000e27] | PoC-green |
| K4-02 | Concentrate-after-fee L recompute leak / virtual≠real | AdvCanonicalFull.testFuzz_canonical_conservation (3000 runs): virtual==real both tokens, global conservation | PoC-green |
| K4-03 | Taker `Aqua.push` in preTransferOutCallback → over-extract + reverse for profit | AdvConcentrateHook (2 tests): pushed value credited to maker; taker net loss; no round-trip profit | PoC-green |
| K4-04 | v1.0.2 fee-skip desyncs `amountNetPulled` → maker short | AdvSkipConc + AdvCanonicalFull (fee bps 0..50%): `_tryPullFee` credits only on landed pull; sufficiency (SwapVM.sol:240) exact | PoC-green + code |
| K4-05 | Fee/Decay ordering non-conservation `[fee][decay][xyc]` vs `[decay][fee][xyc]` + time-warped 2nd swap | AdvFeeDecay.testFuzz_feeDecayXyc: conservation both orderings, both swaps | PoC-green |
| K4-06 | Fee stacking (A+A) double-charges accounting | AdvFeeStack: stacked fees conserve | PoC-green |
| K4-07 | `Calldata.slice` underflow on short args | All ArgsBuilder round-trips revert on mis-size; guarded slice with selector | code |
| K4-08 | Backward `_jump` re-runs a computed curve/fee/concentrate → double settle | AdvBackwardJump (4 tests): xyc/fee/concentrate back-jumps REVERT via `require(amountIn==0||amountOut==0)`; baseline settles once | PoC-green |
| K4-09 | Pegged∘Decay, Pegged∘Fee invariant carry breaks on real Aqua path | AdvInvariantsAqua (3 tests): repo CoreInvariants pass on deployed router + real Aqua | PoC-green |
| K4-10 | WETH-unwrap missing token==WETH guard → cross-actor loss | SwapVM.sol:275-278; non-WETH `safeWithdrawTo` reverts → taker self-grief only | code |
| K4-11 | 3P `Aqua.push`/`ship`/`dock`/`pull` cross-maker corruption | balances keyed `[maker][app][strategyHash][token]`; push credits-only; pull uses app==msg.sender | code |
| K4-12 | Extreme-scale round-trip surplus amplifiable to drain | AdvBoundary at <=1e24: round-trip maker-favorable; surplus is bounded rounding dust (K2-01) | PoC-green |
| K4-13 | Nested runLoop (wrapper instructions) cross-order re-entrancy | AdvNested: nested callbacks bounded, no cross-order settlement | PoC-green |
| K4-14 | Authorization drift: tampered program / foreign token / same-token | AdvAuth: all revert (orderHash binds program; strategyHash gate) | PoC-green |
| K4-15 | Taker levers (dir × exactIn/Out × isFirstTransferFromTaker × useTransferFromAndAquaPush × to × callbacks) break conservation | AdvCanonicalFull + AdvConservation: every lever combination conserves | PoC-green |

---

## Carried-forward kills (campaigns 1–3), still valid against the eligible release

- K1/K2 XYC/Pegged round-trip no-profit at realistic scale (AdvFuzz, AdvBoundary).
- K2-01 extreme-scale surplus is benign non-amplifiable dust within OZ tolerance.
- K3 fee accounting conserves across the full direction × exactIn/Out × ordering × callback matrix.
- Hook-injection as taker-profit killed (stateless 2D concentrate).

---

## Why no kill was reversible into a finding

Each kill resolves to one of three terminal states, none of which is a reportable bug:
1. **Revert** — the attack path is closed (auth, back-jump, foreign token, unwrap mismatch).
2. **Self-harm** — the only party who loses is the actor who chose the action (maker griefing
   own pool; taker injecting/unwrapping against themselves).
3. **Conservative settlement** — value is preserved across {taker, maker, feeTo} to the wei,
   with rounding directed to the pool.

No path produced (a) counterparty theft, (b) profitable price-bound escape, (c) double
settlement, (d) invariant decrease at reachable scale, or (e) virtual/real accounting drift.
