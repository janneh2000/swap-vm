# FIFTH_CANDIDATES

Integration-layer candidates raised in the fifth campaign. Each is a specific mechanism-level
claim of cross-component impact. **None survived** (see KILL_LEDGER for evidence). The two most
material (C5-01 decoder underflow, C5-07 opcode-table divergence) are written in the full
mandatory candidate format; the rest are summarized.

---

### C5-01 — `Calldata.slice` begin>end underflow via taker-controlled slice offsets
- ROOT CAUSE: `Calldata.slice(begin,end,exception)` checks `end ≤ length` but not `begin ≤ end`;
  `res.length = sub(end,begin)` underflows to ~2²⁵⁶ when begin>end.
- AFFECTED COMPONENT / BOUNDARY: `@1inch/solidity-utils` Calldata ⟷ TakerTraits decoder (un-hashed, taker-controlled).
- ATTACKER MODEL: unprivileged taker (fully controls `takerTraitsAndData`).
- PRECONDITION: none beyond calling swap.
- EXACT INPUT: raw takerData header with non-monotonic offsets index_k (e.g. index1<index0).
- EXECUTION PATH: `TakerTraitsLib._getDataSlice` → `Calldata.slice(begin=index_{k-1}, end=index_k)`.
- TRUST ASSUMPTION TESTED: that a malformed taker representation can reach the maker's accounting.
- SECURITY INVARIANT: maker real==virtual and curve-bound settlement regardless of taker encoding.
- CONTROL CASE: canonical builder takerData → normal swap.
- MALICIOUS CASE: hand-crafted underflowing offsets.
- SEMANTIC DIFFERENCE: huge-length calldata slice for a taker field.
- TOKEN/FUND FLOW: none to the taker's benefit — length-gated fields fall to safe defaults
  (threshold/to/deadline waived = taker self-harm); content fields (hookData/callbackData/
  instructionsArgs) are self-scoped; huge lengths OOG on ABI-copy → revert.
- MAKER IMPACT: none (unreachable). TAKER IMPACT: self-DoS or waived own protection. PROFIT: none.
- REPEATABILITY / CAPITAL: n/a.
- LOCAL REPRO: `AdvIntegrationDecode.t.sol` (3 tests, incl. 256-run fuzz over offsets+tail).
- FALSIFICATION: fuzz asserts maker real==virtual & curve-bound on success, revert otherwise — held.
- HISTORICAL COVERAGE: matches OZ **M-3 "Calldata.slice underflow"**; the `end≤length` check is
  the M-3 fix. The residual begin>end path is non-exploitable here.
- NOVELTY: none (known area); no new security primitive.
- SEVERITY: none (informational / defense-in-depth: add `begin≤end` assert). **KILLED (K5-01).**

### C5-07 — Opcode-table divergence between AquaOpcodes and base Opcodes
- ROOT CAUSE: the two routers map the same opcode number to different instructions.
- BOUNDARY: SDK/program ⟷ router opcode table; router A ⟷ router B.
- ATTACKER MODEL: unprivileged taker attempting to execute an order on the "wrong" router.
- PRECONDITION: would require an order authorized for router A to execute on router B.
- EXECUTION PATH: `runLoop` dispatch `ctx.vm.opcodes[opcode]`.
- TRUST ASSUMPTION TESTED: that an order is bound to a single router.
- SECURITY INVARIANT: an order executes only where its liquidity/authorization lives.
- CONTROL CASE: swap on the correct router (works).
- MALICIOUS CASE: same order on a second AquaSwapVMRouter.
- SEMANTIC DIFFERENCE: identical bytes → different instructions per router.
- FUND FLOW: none — router B has empty balances for (maker, routerB, hash) → revert; sig orders
  fail EIP-712 domain (verifyingContract) on router B.
- MAKER/TAKER IMPACT: none from an attacker. It IS a maker/SDK footgun (build against wrong table
  → your own strategy misexecutes/reverts).
- LOCAL REPRO: `AdvIntegrationRouter.t.sol` (cross-router execution reverts; router1 intact).
- FALSIFICATION: confirmed hash is router-independent yet execution still fails cross-router.
- HISTORICAL COVERAGE: not a prior finding, but the binding is the same one the audits relied on.
- NOVELTY: the divergence observation is new; the *security consequence* is nil (bound).
- SEVERITY: none as an attack; **hardening note** (program version/table tag). **KILLED (K5-07).**

---

### Summarized candidates (all KILLED — see KILL_LEDGER)

- **C5-02 orderHash ⟷ program non-canonical ABI split** — hash re-encodes the decoded order; program is a slice of the same decoded data. No split. (K5-02)
- **C5-03 dynamic fee provider abuse** — provider is maker-chosen, staticcall-isolated, feeBps≤100%, to≠0, maker-pays; no global provider. (K5-03)
- **C5-04 token semantics (FoT/rebasing/ERC777)** — maker-inventory-scoped; CEI + per-order lock; taker can't force it on a standard-token maker; reverts not extracts. (K5-04)
- **C5-05 quote/swap divergence** — amounts identical; only fee-movement/interface differ; no funds move on quote; taker keeps threshold. (K5-05)
- **C5-06 stale-snapshot across callback boundary** — sufficiency check re-reads live balance vs fixed baseline; push=donation; amountNetPulled only from landed in-loop pulls. (K5-06)
- **C5-08 cross-order shared state ("A poisons B")** — no global mutable economic state; balances partitioned by (maker,app,hash,token); transient lock per order. (K5-08)
- **C5-09 Extruction register-replacement / cross-order reentry** — bounded by Aqua balance (can't conjure), taker amount-binding (can't overcharge), and per-order lock; maker-chosen target. (K5-09)
- **C5-10 CalldataPtr 128-bit offset/length packing overlap** — only triggered by a maker-controlled underflowed program length (index3>data.length in hashed traits); maker self-harm. (K5-10)
- **C5-11 cross-chain replay (CREATE3 same address)** — sig: chainId in domain; aqua: per-chain on-chain ship. No fund replay. (K5-11)
- **C5-12 WETH-unwrap on non-WETH tokenOut / router dust** — non-WETH withdraw reverts (self-DoS); WETH.withdraw burns exact amount, no dust; owner-rescuable. (K5-12)

## Promotions

**0 candidates promoted.** No integration mechanism produced a novel, in-scope, reachable,
unprivileged, reproducible, material-impact vulnerability. Nothing manufactured.
