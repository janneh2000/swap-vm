# THIRD CAMPAIGN POC MATRIX

Harness: Foundry 1.5.1 + solc 0.8.30 vs AquaSwapVMRouter(v1.0.2)+Aqua(v1.0.0).
Run: forge test --offline --use ~/.svm/0.8.30/solc-0.8.30 --match-path 'test/adv/AdvInvariantsAqua.t.sol' -vv

| test | composition | invariants checked | result |
|------|-------------|--------------------|--------|
| test_inv_pegged_aqua | PeggedSwap (aqua) | symmetry, quote/swap, monotonicity, additivity, rounding-favors-maker, balance-suff | PASS |
| test_inv_pegged_decay_aqua | Decay->PeggedSwap (aqua) | symmetry, quote/swap, monotonicity, rounding, balance-suff (additivity skipped: decay is intentionally sub-additive/stateful) | PASS |
| test_inv_pegged_fee_aqua | aquaFee->PeggedSwap (aqua) | quote/swap, monotonicity, additivity, balance-suff (spot/symmetry skipped: fee alters effective spot) | PASS |

No malicious-case PoC (no invariant broke). Deterministic, non-fuzz (fixed realistic params: reserves 1e21,
A=100e27, amounts {1,10,50}e18).
