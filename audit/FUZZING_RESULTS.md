# FUZZING RESULTS

All against AquaSwapVMRouter(v1.0.2)+Aqua(v1.0.0), real ship/swap. Green = property held every run.

| PoC | property | runs | result |
|-----|----------|------|--------|
| AdvComposition | round-trip A->B->A never profits taker: XYC, Pegged, Pegged+Decay | fixed | PASS (loses ~1 wei = maker-favorable) |
| AdvFuzz.testFuzz_pegged_roundtrip | pegged round-trip no-profit, asymmetric x0/y0, A in [0,5000e27], both dirs | 2000+ | PASS |
| AdvFuzz.testFuzz_peggedDecay_roundtrip | Pegged+Decay round-trip no-profit, warp in [0,200000] | 2000+ | PASS |
| AdvFuzz.testFuzz_xyc_conservation | XYC swap does not revert-inconsistently over arbitrary reserves/amount | 2000+ | PASS |
| AdvConservation.testFuzz_conservation_callback | fee(0..100%) settlement conservation, callback pay, dir×exactIn/Out×firstFromTaker; register==real + global conservation | 4000 | PASS |
| AdvConservation.testFuzz_conservation_tfap | same, useTransferFromAndAquaPush pay path | 4000 | PASS |
| AdvSkipConc.testFuzz_feeSkip_conservation | v1.0.2 best-effort fee SKIP (maker can't cover): taker exact, feeTo gets 0, register==real | 5000 | PASS |
| AdvSkipConc.testFuzz_concentrate_roundtrip | XYCConcentrate(+Decay) round-trip no-profit at fuzzed price bounds | 5000 | PASS |
| AdvFeeDecay.testFuzz_feeDecayXyc | canonical [aquaFee][Decay][XYC] (both orderings, 2 swaps w/ active decay), dir×exactIn/Out×firstFromTaker: exact conservation + register==real | 6000 | PASS |
| AdvFeeStack.testFuzz_stacked_fees_conservation | TWO stacked aqua fees (distinct recipients): exact conservation + register==real | 5000 | PASS |
| AdvNested.test_nested_cross_order_no_profit | swap(B) nested in swap(A) callback, same maker: no value extraction (paid 20B, got 18.18A) | fixed | PASS |
| AdvAuth (x3) | cannot strip fee instr / use foreign token / same-token: all revert | fixed | PASS |
| AdvBoundary.testFuzz_pegged_realistic_roundtrip | Pegged(+Decay,+rate/decimal asymmetry) round-trip maker-favorable, reserves<=1e24 | 8000 | PASS |
| AdvPeggedMin.test_scan_scales | round-trip surplus vs scale: LOSS <=1e24; +4 wei @1e27; +4000 wei @1e30 | fixed | PASS (characterization) |
| AdvPeggedMin.test_amplify_realistic | 500 round-trips @1e24: net LOSS (non-amplifiable) | fixed | PASS |

Key checks embedded in every conservation test:
- taker position change == (-amountIn tokenIn, +amountOut tokenOut) exactly (register == what the taker gets).
- maker REAL wallet delta == maker AQUA VIRTUAL delta, both tokens (no register<->real divergence).
- Σ real deltas per token across {taker, maker, feeTo(s)} == 0 (no tokens created/destroyed).
