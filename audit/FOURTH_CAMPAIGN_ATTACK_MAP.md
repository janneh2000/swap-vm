# FOURTH_CAMPAIGN_ATTACK_MAP

Phases 4–12. The concrete attack surface enumerated by *primitive* and *actor*, with the
attack idea, the mechanism it would need, and the PoC that tested it. This is the map of
"what could go wrong and who could cause it," independent of historical severity.

Actors: **T** = taker (fully adversarial, controls TakerTraits + callbacks + amounts + direction),
**M** = maker (authors program + hooks; can only harm own pool), **3P** = arbitrary third
party (can call externally-reachable Aqua funcs: push, dock, ship own strategy).

---

## 1. Curve/value primitives (RC-1/RC-2)

| Attack | Actor | Mechanism required to win | PoC | Outcome |
|--------|-------|---------------------------|-----|---------|
| Round-trip profit on XYCSwap | T | k decreases across a buy+sell | AdvFuzz.testFuzz_xyc_* | No profit; k non-decreasing |
| Round-trip on PeggedSwap | T | C decreases | AdvFuzz / AdvBoundary / AdvPeggedInvariant | No profit; C non-decreasing |
| Round-trip on Concentrate | T | L shrinks / rounding leaks | AdvSkipConc / AdvConcentrateHook | No profit |
| Round-trip on canonical full program | T | any of the above ∘ fee | **AdvCanonicalFull.no_roundtrip** | No profit (3000 runs) |
| Value leak only at extreme scale (>=1e25) | T | amplifiable wei surplus | AdvBoundary + KILL K2-01 | Non-amplifiable rounding dust within OZ tolerance; not reachable at realistic scale |

## 2. Accounting / settlement primitives (RC-3)

| Attack | Actor | Mechanism | PoC | Outcome |
|--------|-------|-----------|-----|---------|
| Virtual≠real drift on any swap | T | Aqua ledger diverges from ERC20 move | every conservation PoC | virtual==real always |
| Sufficiency bypass via `useTransferFromAndAquaPush` | T | push path skips the `>=` check unsafely | AdvConservation.tfap / AdvCanonicalFull | conserved; push path pulls exact amountIn |
| Sufficiency bypass via `isFirstTransferFromTaker` ordering | T | reorder transfer vs compute to underpay | AdvCanonicalFull (fuzzed) / AdvConservation | conserved |
| `amountNetPulled` desync via fee-skip | T/M | credit fee not actually pulled | AdvSkipConc / AdvCanonicalFull | credited only on landed pull; exact |

## 3. Re-execution / interpreter primitives (RC-4)

| Attack | Actor | Mechanism | PoC | Outcome |
|--------|-------|-----------|-----|---------|
| Backward `_jump` re-runs a curve → double push | M (program-bound; T cannot craft) | recompute after amounts set | **AdvBackwardJump.xyc/fee/concentrate** | all REVERT (recompute guard) |
| Baseline (no back-jump) single settle | — | control | **AdvBackwardJump.baseline** | single conservative settle |
| Nested `runLoop` (Fee/Decay/Concentrate wrappers) re-entrancy | T | nested call double-settles or crosses orders | AdvNested | bounded; no cross-order effect |

## 4. Authorization primitives (RC-5)

| Attack | Actor | Mechanism | PoC | Outcome |
|--------|-------|-----------|-----|---------|
| Execute a program the maker didn't authorize | T/3P | orderHash≠strategyHash accepted | AdvAuth (tampered program) | REVERTS |
| Swap a token pair the strategy didn't ship | T | foreign token accepted | AdvAuth (foreign token) | REVERTS |
| Same-token in==out | T | degenerate self-swap drains | AdvAuth (same token) | REVERTS |
| Sig-mode loose binding | T | mutate program under a signature | AUTHORIZATION_MAP §sig | order hash covers program; REVERTS |

## 5. Hook / callback primitives (RC-7)

| Attack | Actor | Mechanism | PoC | Outcome |
|--------|-------|-----------|-----|---------|
| Taker pushes tokenOut mid-callback to bypass bounds, then reverses | T | pushed value recoverable by pusher | **AdvConcentrateHook** | pushed value credited to MAKER; taker net loss; no profit |
| Maker hook injects to move price | M | cross-actor theft | POST_FIX_MAP F-3 | maker-scoped only |
| Callback re-enters swap on same order | T | re-entrancy double-spend | AdvNested | bounded, conserved |

## 6. Externally-reachable Aqua primitives (RC-6/RC-7, actor 3P)

| Attack | Actor | Mechanism | PoC / analysis | Outcome |
|--------|-------|-----------|----------------|---------|
| `Aqua.push` arbitrary app/strategy | 3P | credit or grief a victim maker | AdvConcentrateHook + REACHABILITY_MAP | push only *credits* the target; cannot extract |
| `Aqua.ship` re-init live strategy | M | reset balances / alias | STATE_MODEL | maker-scoped; no cross-maker aliasing (strategyHash keyed by maker) |
| `Aqua.dock`/`pull` on foreign balance | 3P | pull another maker's funds | REACHABILITY_MAP | `pull` app==msg.sender; balances keyed by maker+app+hash; no foreign pull |

## 7. WETH-unwrap edge (OZ Low "will resolve")

| Attack | Actor | Mechanism | Analysis | Outcome |
|--------|-------|-----------|----------|---------|
| tokenOut unwrap with non-WETH token | T | `IWETH(token).safeWithdrawTo` on non-WETH | SwapVM.sol:275-278 has no token==WETH guard | non-WETH `withdraw` reverts → taker self-grief only; no cross-actor impact |

---

## Coverage statement

Every (primitive × actor) cell above was either exercised by a runnable PoC or closed by a
read-confirmed structural guard. The cells that a fully-adversarial **taker** or **third party**
can reach all resolve to: revert, self-harm, or conservative settlement. The only cells that
produce a value change unfavorable to someone are **maker-scoped** (a maker harming their own
pool) or **protocol-fee-revenue** (already the accepted v1.0.2 Low). No cell yields
counterparty theft, price-bound escape for profit, or double-settlement.
