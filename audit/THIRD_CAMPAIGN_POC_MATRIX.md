# THIRD CAMPAIGN POC MATRIX (Foundry 1.5.1 + solc 0.8.30 vs AquaSwapVMRouter v1.0.2 + Aqua v1.0.0)

Run: forge test --offline --use ~/.svm/0.8.30/solc-0.8.30 --match-path 'test/adv/*' --fuzz-runs 5000 -vv

| PoC | attacks audit finding | runs | result |
|-----|-----------------------|------|--------|
| AdvPeggedInvariant.t.sol | OZ Critical-1 (precision) + Critical-3 (axis): invariant C non-decrease | 4×5000 | PASS (C holds; near-zero A, asym anchors, reverse dir, rates) |
| AdvConcentrateHook.t.sol | OZ Medium hook-injection (taker preTransferOutCallback vector) | 4000 + fixed | PASS (taker loss; no gain) |
| AdvInvariantsAqua.t.sol | repo CoreInvariants on untested Aqua-mode compositions | fixed | PASS (Pegged, Pegged+Decay, Pegged+Fee) |
| (campaign 2) AdvConservation/AdvFeeStack/AdvSkipConc/AdvFuzz/AdvNested/AdvBoundary/AdvAuth | fee accounting, skip, stacked, round-trips, cross-order, auth binding | 3–8k each | PASS |

No malicious-case PoC exists (no invariant broke; no taker profit found).
