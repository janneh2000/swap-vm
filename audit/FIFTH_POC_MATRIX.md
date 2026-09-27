# FIFTH_POC_MATRIX

Runnable evidence for the fifth (integration) campaign. All tests target the deployed
`AquaSwapVMRouter → AquaOpcodes` + real `Aqua`. Files in `test/adv/`, mirrored to
`audit/FINAL_POC/`.

Run:
```
export PATH="$HOME/.foundry/bin:$PATH"; export FOUNDRY_OFFLINE=true
forge test --use ~/.svm/0.8.30/solc-0.8.30 --match-path 'test/adv/AdvIntegration*.t.sol' -vv
```
Full adversarial suite (all campaigns): `--match-path 'test/adv/*'` → **18 files, 41 tests, 0 failed.**

## New in the fifth campaign (integration boundary)

| File | Test | Boundary / candidate | Result |
|------|------|----------------------|--------|
| AdvIntegrationDecode.t.sol | test_handcrafted_minimal_swap_ok | raw TakerTraits header decodes to a normal swap | PASS |
| AdvIntegrationDecode.t.sol | testFuzz_malformed_offsets_cannot_drain_maker | C5-01 Calldata underflow via taker offsets (256 runs) | PASS |
| AdvIntegrationDecode.t.sol | test_threshold_waiver_is_self_harm | C5-01 waiving threshold is self-scoped | PASS |
| AdvIntegrationExtruction.t.sol | test_extruction_cannot_conjure_funds | C5-09 Extruction can't pull beyond maker balance | PASS |
| AdvIntegrationExtruction.t.sol | test_extruction_cannot_force_taker_overpay | C5-09 taker amount-binding | PASS |
| AdvIntegrationExtruction.t.sol | test_extruction_within_balance_conserves | C5-09 real==virtual, maker-only | PASS |
| AdvIntegrationRouter.t.sol | test_cross_router_execution_fails_safe | C5-07 opcode-table divergence neutralized by app-key binding | PASS |

## Coverage of the campaign's mandatory phases by PoC or analysis

| Phase | Covered by |
|-------|-----------|
| 1 deployment topology | FIFTH_DEPLOYMENT_MAP (source + broadcast) |
| 2 router/core mismatch | AdvIntegrationRouter + FIFTH_ROUTER_CORE_DIFF |
| 3 SDK/program construction | AdvIntegrationDecode + FIFTH_SDK_PROGRAM_ANALYSIS |
| 4 order-hash/program binding | AdvIntegrationRouter + FIFTH_ORDER_BINDING_MAP (+ AdvAuth, campaign 4) |
| 5 dynamic fee provider | FIFTH_FEE_PROVIDER_ANALYSIS (staticcall/maker-scoped; code-proven) |
| 6 deployment config | FIFTH_DEPLOYMENT_MAP (no attacker-settable config) |
| 7 ABI/calldata | AdvIntegrationDecode + Calldata/VM code trace |
| 8 token semantics | FIFTH_TOKEN_SEMANTICS (CEI code-proven) |
| 9 callback boundary | AdvIntegrationExtruction + FIFTH_CALLBACK_BOUNDARY |
| 10 cross-order shared state | FIFTH_SHARED_STATE_MAP (+ AdvNested, campaign 4) |
| 11 quote/router/VM triangulation | FIFTH_ROUTER_CORE_DIFF §2 |
| 12 legacy/version drift | AdvIntegrationRouter + FIFTH_ROUTER_CORE_DIFF §1 |
| 13 integration business logic | AdvIntegrationExtruction + FIFTH_SEMANTIC_DIFFERENTIALS |
| 14 integration fuzzer | AdvIntegrationDecode (semantic-differential fuzz) |
| 15 exploit economics | FIFTH_KILL_LEDGER terminal-states + FINAL assessment |
| 16 duplicate firewall | FIFTH_DUPLICATE_LEDGER |

## "PASS" semantics

- Decode fuzz: maker `real==virtual` and curve-bound movement on success, else revert (a single
  wei of maker drift, or any maker loss beyond amountOut, would fail).
- Extruction: fund-conjuring reverts; taker-overcharge reverts; within-balance conserves.
- Router: cross-router execution reverts; the shipped-router balances remain intact.

The ~90M mean gas on the decode fuzz (vs ~845k median) is the expected self-DoS: underflowed
huge-length slices burn gas on ABI-copy and revert — a taker griefing their own transaction, not
a maker attack.
