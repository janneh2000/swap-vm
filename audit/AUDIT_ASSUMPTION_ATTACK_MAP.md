# AUDIT ASSUMPTION ATTACK MAP (grounded in the real audit archive)

Source: full 1inch/1inch-audits archive obtained this campaign — "Aqua and SwapVM v1" (OpenZeppelin,
Theori, MixBytes, Decurity, Bailsec, Hexens, Nethermind, Hashlock) and "Aqua and SwapVM v1.0.2"
differential (OZ, Theori, MixBytes, Bailsec, Decurity). Eligible release v1.0.2 (32c687c) = v1 code +
the Fee best-effort change; v1 fixes ship in v1.0.2. Method: for each fixed Critical/High, attack the
fix's assumption on the eligible code with the Foundry harness.

## v1.0.2 differential (scope = ONLY src/instructions/Fee.sol)
- OZ M-01: Aqua fee silently lost when fee token blocks maker/recipient. Acknowledged (one-sided strategy).
  Fee-revenue-loss only; taker pays quoted amount. NOT taker theft. (matches my campaign-2 skip-path fuzz)
- OZ L-01 (event not indexed), N-01 (non-Aqua fee no zero-recipient check): acknowledged, cosmetic/footgun.
- Theori v1.0.2: 0 findings. All 5 firms: no settlement break / no taker underpayment.
⇒ The novel v1.0.2 code (best-effort fee) is confirmed taker-neutral by 5 firms AND by my conservation
   fuzzing (register==real across the full matrix, skip path, stacked fees). Nothing to attack here.

## v1 Criticals/Highs — fix present in v1.0.2? attacked? result
| finding (auditor) | fix (PR) | present in v1.0.2? | 2nd-order attack | RESULT |
|---|---|---|---|---|
| C: PeggedSwap solve() precision loss → C decreases (maker loss, >15% drainable) (OZ/MixBytes/Theori/Hashlock) | stable formula `w=2R·ONE/(ONE+√D)` (#67) | YES (PeggedSwapMath.sol:106-112) | measure invariant C non-decrease across near-zero A (unstable region), asym anchors, both dirs, exactIn/out, rates | **HOLDS** — AdvPeggedInvariant, 4×5000 runs, C never materially decreases |
| C: PeggedSwap axis mismatch on reverse swap w/ asym capacity → drainage (OZ/Theori#1) | `parseRatesAndBalances` dir-based (#68) | YES (PeggedSwap.sol:71-79) | reverse-direction + asymmetric anchors invariant-C test | **HOLDS** — same fuzz, reverse dir preserves C |
| C: XYCConcentrate shared-liquidity multi-token cyclic arb (OZ/Nethermind/MixBytes) | drop multi-token; make Concentrate STATELESS 2-token (#82) | YES (XYCConcentrate.sol stateless, no _updateScales/liquidity storage) | multi-token cyclic arb (campaign 1: marginal-neutral for XYC); concentrate round-trips | **HOLDS** — stateless; no shared-liquidity slot to corrupt |
| H: XYCConcentrate records wrong balances w/ protocol fee (OZ/Decurity) | stateless concentrate + README ordering (#75,#82) | YES (stateless ⇒ records nothing) | concentrate+fee conservation | **HOLDS** — AdvSkipConc/AdvFeeStack conserve |
| H: DynamicBalances doesn't account instant fees (OZ) | amountNetPulled + README ordering (#75) | Balances NOT in AquaOpcodes (live router) | n/a on deployed router | out-of-scope on live router |

## Medium/Low that are LIVE (acknowledged / doc-only) in v1.0.2 — attacked for taker theft
| finding | status | taker-exploitable? | my check |
|---|---|---|---|
| Hook token injection bypasses concentrated price bounds (OZ M) | "will resolve" via docs for MAKERS | injection vector is the TAKER's preTransferOutCallback (always available) | **NO** — AdvConcentrateHook: over-extraction via injection is pure taker LOSS (paid 500 A + injected 100 B, got 49999 wei B); round-trip fuzz 4000 runs no gain. Statelessness removed the state-corruption impact. KILLED |
| Strategy reinit via ship (disjoint tokens, same hash) (OZ M) | acknowledged | needs maker to reuse hash across pairs (no unique salt) | maker-config; XYC cross-pair marginal-neutral; PeggedSwap cross-pair needs anchor==reserve (maker) |
| Unrestricted Aqua.push (OZ M) | acknowledged | self/donation only | NO extraction (campaign 1 proven) |
| Calldata.slice begin>end underflow (OZ M) | acknowledged | program offsets are maker-signed/shipped; takerData offsets are taker's own | self-harm/OOG only (campaign 1 C-06); not cross-party |
| Fee revert if maker lacks tokenIn (OZ M); fee-on-fee exactOut (OZ M) | acknowledged | liveness/maker-config; taker verifies via quote | DoS/maker-config, not theft |
| Extruction quote/swap divergence (OZ M); maker-controlled target (Theori#4) | doc | maker-chosen target; taker slippage-protected | maker/strategy risk (campaign 1/2) |
| Decay stores pre-fee amountIn (OZ M); Decay underflow (OZ note); jump uint16 (fixed #93) | doc/acknowledged | over-compensation favors MAKER; underflow = DoS | not taker theft |

## Conclusion of the attack map
Every fixed Critical/High holds under adversarial fuzzing on the eligible code. Every LIVE
acknowledged finding is fee-revenue-loss, DoS/liveness, maker-config, or maker/strategy risk — none is a
novel unprivileged-taker theft. No new root cause found.
