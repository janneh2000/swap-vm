# FOURTH_CAMPAIGN_POC_MATRIX

The runnable evidence. Every PoC is a Foundry test against the eligible release
(SwapVM v1.0.2 / Aqua v1.0.0) via the **deployed** `AquaSwapVMRouter → AquaOpcodes` and the
**real** `Aqua` ledger (not sig-mode/StaticBalances). Files live in `test/adv/` of the
scope checkout and are mirrored into `audit/FINAL_POC/`.

Run command:
```
export PATH="$HOME/.foundry/bin:$PATH"; export FOUNDRY_OFFLINE=true
forge test --use ~/.svm/0.8.30/solc-0.8.30 --match-path "test/adv/*"
```

Latest full-suite result: **15 test suites · 34 tests · 34 passed · 0 failed.**

---

## New in the fourth campaign

| File | Tests | Purpose (root cause) | Runs | Result |
|------|-------|----------------------|------|--------|
| AdvCanonicalFull.t.sol | testFuzz_canonical_conservation | Full deployed program `[aquaProtocolFee][concentrate][xycSwap]`: virtual==real both tokens, global conservation, taker registers==real, across dir × exactIn/Out × isFirstTransferFromTaker × useTransferFromAndAquaPush × fee bps 0..50% (RC-3/RC-8) | 3000 | PASS |
| AdvCanonicalFull.t.sol | testFuzz_canonical_no_roundtrip_profit | Same program: buy tout then sell back; taker cannot end up on the start token (RC-1/RC-2) | 3000 | PASS |
| AdvBackwardJump.t.sol | test_backjump_xyc_reverts | `[xycSwap][jump→0]` re-run → recompute guard revert (RC-4) | — | PASS |
| AdvBackwardJump.t.sol | test_backjump_fee_reverts | `[fee][xyc][jump→0]` → revert (RC-4) | — | PASS |
| AdvBackwardJump.t.sol | test_backjump_concentrate_reverts | `[concentrate][xyc][jump→0]` → revert (RC-4) | — | PASS |
| AdvBackwardJump.t.sol | test_forward_baseline_settles_once | control: no jump → single conservative settle (real drop==virtual drop==amountOut) | — | PASS |

## Carried-forward PoCs (campaigns 1–3), all re-run green in the eligible release

| File | Tests | Root cause covered |
|------|-------|--------------------|
| AdvComposition.t.sol | composition matrix | RC-3 program composition |
| AdvFuzz.t.sol | xyc / pegged / pegged∘decay round-trip + conservation | RC-1/RC-2 |
| AdvConservation.t.sol | callback path, useTransferFromAndAquaPush path | RC-3/RC-7 |
| AdvNested.t.sol | nested runLoop wrapper re-entrancy | RC-4/RC-7 |
| AdvSkipConc.t.sol | fee-skip conservation, concentrate round-trip | RC-8/RC-2 |
| AdvFeeStack.t.sol | stacked fees | RC-8 |
| AdvFeeDecay.t.sol | `[fee][decay][xyc]` both orderings + time-warp 2nd swap | RC-8/RC-3 |
| AdvAuth.t.sol | tampered program / foreign token / same-token | RC-5 |
| AdvBoundary.t.sol | pegged (+decay) realistic-scale round-trip | RC-1 |
| AdvPeggedMin.t.sol | pegged minimal/edge | RC-1 |
| AdvPeggedInvariant.t.sol | C non-decreasing: smallA / asymmetric / rates | RC-1/RC-2 |
| AdvInvariantsAqua.t.sol | repo CoreInvariants on Pegged, Pegged∘Decay, Pegged∘Fee over real Aqua | RC-1/RC-2/RC-3 |
| AdvConcentrateHook.t.sol | taker push-injection over-extract + reverse | RC-7 |

---

## What "PASS" means per test type

- **Conservation tests** assert equalities to the **wei**: `takerΔ == amountIn/Out`,
  `makerΔreal == makerΔvirtual` for both tokens, and `Σ = 0` across {taker, maker, feeTo}.
  A single wei of drift fails the test.
- **Round-trip tests** assert the adversary cannot end with more of the token they started
  with after buy+sell (the economic-theft proxy).
- **Invariant tests** assert the pool's conserved quantity (C, L, k) does not decrease beyond
  a 1e-18-relative tolerance (rounding is required to favor the pool).
- **Revert tests** assert the attack path reverts (auth, back-jump re-execution, bad args).

No PoC was written that "passes" by catching an unrelated revert: the ~0.9–1.1M gas averages
on the fuzz suites confirm the swap bodies execute; the conservation/round-trip assertions
fire on real settled swaps.
