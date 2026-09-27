# FIFTH_INTEGRATION_FUZZ_RESULTS

Phase 14 — the semantic-differential / integration-level tests (not another core-invariant suite).
These drive the SDK-layer/decoder/router boundary directly, building representations two ways and
comparing intended vs actual meaning. All run against the deployed AquaSwapVMRouter + real Aqua.

Run:
```
export PATH="$HOME/.foundry/bin:$PATH"; export FOUNDRY_OFFLINE=true
forge test --use ~/.svm/0.8.30/solc-0.8.30 --match-path 'test/adv/AdvIntegration*.t.sol' -vv
```

## New fifth-campaign integration tests

| File · test | Boundary attacked | Assertion | Result |
|-------------|-------------------|-----------|--------|
| AdvIntegrationDecode · test_handcrafted_minimal_swap_ok | raw 22-byte TakerTraits header (bypass builder) | hand-built takerData executes a normal, conservative swap | PASS |
| AdvIntegrationDecode · testFuzz_malformed_offsets_cannot_drain_maker | non-monotonic taker slice offsets → `Calldata.slice` begin>end underflow | swap reverts OR maker real==virtual and moves by exactly curve amounts | PASS (256 runs; mean gas ~90M shows huge-length slices self-DoS via OOG-on-copy, median ~845k = normal swaps) |
| AdvIntegrationDecode · test_threshold_waiver_is_self_harm | offset makes threshold length≠32 | threshold waived (taker's own loss), maker still pays only curve amountOut | PASS |
| AdvIntegrationExtruction · test_extruction_cannot_conjure_funds | maker-chosen Extruction target forces amountOut ≫ maker balance | Aqua.pull underflows → revert (no third-party drain) | PASS |
| AdvIntegrationExtruction · test_extruction_cannot_force_taker_overpay | target forces amountIn ≠ taker's declared exactIn amount | `TakerTraits.validate` reverts (taker can't be overcharged) | PASS |
| AdvIntegrationExtruction · test_extruction_within_balance_conserves | target replaces registers within maker balance | real==virtual both tokens; only this maker touched | PASS |
| AdvIntegrationRouter · test_cross_router_execution_fails_safe | opcode-table divergence via cross-router execution | Aqua orderHash is router-independent, yet executing on a 2nd router reverts (empty balances); router1 balances intact | PASS |

## What the fuzzer computed per case (intended vs actual)

For `testFuzz_malformed_offsets_cannot_drain_maker`, over random (index0..index9, tail, amount):
- INTENDED: a normal exactIn swap of `amount` tokenB→tokenA against the maker's curve.
- ACTUAL: either a revert (malformed representation) or a settlement in which the **maker's**
  `real tokenIn gain == amountIn`, `real tokenOut loss == amountOut`, and `virtual == real` for
  both tokens. The taker's malformed offsets never moved the maker's balances off the curve.

## Aggregate

New integration tests: **7 (3 files).** Combined with the carried-forward adversarial suite the
full `test/adv/*` run is **18 files, 41 tests, 0 failures.** No integration test surfaced an
attacker-favorable divergence; the ones designed to attempt a break either revert or settle on
the maker's curve.
