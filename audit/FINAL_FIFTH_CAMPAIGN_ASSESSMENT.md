# FINAL FIFTH-CAMPAIGN ASSESSMENT — Integration / trust-boundary hunt

**Program:** HackenProof "1inch Aqua" (authorized whitehat research).
**Eligible release:** SwapVM v1.0.2 (`32c687c`), Aqua v1.0.0 (`81c26e4`); deployed
**AquaSwapVMRouter → AquaOpcodes** + real **Aqua** ledger.
**Mandate:** stop re-hammering core invariants; attack the INTEGRATION layer — deployment,
router topology, SDK/program construction, order-hash binding, fee providers, ABI/calldata,
token semantics, callbacks, shared state, version drift — for a novel, in-scope, **reachable,
unprivileged**, reproducible, material-impact bug.

---

## Verdict

**No novel, in-scope, reachable, unprivileged, reproducible integration vulnerability was found.**

This does not assert the system is unconditionally safe; it reports that the integration
trust-boundaries enumerated by the mission are, in the eligible release, closed against an
unprivileged attacker — by two structural bindings that recur everywhere:

1. **Order↔router↔liquidity binding.** Aqua balances are keyed by `(maker, executing-router,
   strategyHash, token)` and signatures by the EIP-712 domain `(chainId, verifyingContract)`. An
   order can only execute where its liquidity/authorization lives. This single fact neutralizes
   the campaign's most promising structural observation — the **opcode-table divergence** between
   AquaOpcodes and base Opcodes (same bytes, different instructions per router).
2. **Program↔hash binding.** In both modes the hash covers the full order including the program
   (Aqua re-encodes the decoded order; sig hashes `keccak256(data)`), and the program is a
   calldata slice of that same hashed data — so there is no "authorized-as-X, executed-as-Y."

Around those, the taker-controlled surface is self-scoped (threshold/deadline/recipient waivers
are self-harm; `push` in a callback donates to the maker), the one external in-loop call (dynamic
fee provider) is maker-chosen and staticcall-isolated, the escape hatch (Extruction) is bounded
by Aqua balance and taker amount-binding, and there is no shared mutable economic state for one
order to poison another.

## What was genuinely new this campaign

- **Three integration PoCs** exercising boundaries the prior campaigns never touched (they always
  used the canonical builders and one router):
  - `AdvIntegrationDecode` — hand-crafted, malformed `takerData` (raw header, non-monotonic slice
    offsets) driving the `Calldata.slice` `begin>end` underflow; proves the maker's accounting is
    unreachable (256-run fuzz: revert or maker real==virtual & curve-bound).
  - `AdvIntegrationExtruction` — the register-replacing escape hatch can't conjure funds, can't
    overcharge the taker, and conserves within the maker's balance.
  - `AdvIntegrationRouter` — cross-router execution fails safe, neutralizing the opcode-table
    divergence.
- **Two structural observations** documented for the first time: the **opcode-table divergence**
  (ROUTER_CORE_DIFF §1) and the **`Calldata.slice begin>end` residual** (KILL K5-01). Both are
  real; neither is an unprivileged vulnerability.

Full adversarial suite across all campaigns: **18 files, 41 tests, 0 failures.**

## Honest hardening notes (not bounty findings; defense-in-depth)

1. **`Calldata.slice` should assert `begin ≤ end`.** The audited M-3 fix added `end ≤ length`
   only; a `begin ≤ end` assert would turn today's self-DoS/silent-underflow into a clean revert.
2. **Program/opcode-table versioning.** A per-router opcode namespace or a version/table tag in
   the program would convert a wrong-table build from silent misexecution into a clean revert
   (SDK/router coupling is currently an implicit contract).
3. **Continue emitting/monitoring `ProtocolFeeSkipped`** (already the v1.0.2 design) — the
   integration assumption that off-chain monitoring watches it is load-bearing for protocol
   revenue (not user safety).

## Residual open items (all known / out-of-scope-to-exploit)

| Item | Class | Why not a bounty finding |
|------|-------|--------------------------|
| Dynamic-fee provider correctness | external maker-chosen contract | out of eligible scope; maker-pays; staticcall-isolated |
| Extruction target correctness | external maker-chosen contract | out of scope; bounded by Aqua + taker binding |
| FoT/rebasing/ERC777 as maker inventory | unsupported token class | maker-scoped; CEI + per-order lock prevent cross-user theft |
| WETH-unwrap non-WETH guard | OZ Low "will resolve" | taker self-DoS only |
| SDK opcode-table coupling | integration footgun | maker/integrator correctness, not attacker-reachable |

## Cumulative position across five campaigns

Campaigns 1–4 exhausted the core-contract invariants (curves, fees, decay, concentrate, pegged,
settlement conservation, authorization, backward-jump, canonical composition). Campaign 5
exhausted the integration/trust-boundary surface the mission specified. Across all five, **no
novel exploitable vulnerability has survived**, and nothing has been manufactured. The genuinely
remaining frontier is **outside the eligible in-scope contracts** — the off-chain TS SDK, and the
maker-authored fee-provider / Extruction target contracts — which would require explicit scope
confirmation (and, for the SDK, its source) before further effort.

## Reproduce

```
export PATH="$HOME/.foundry/bin:$PATH"; export FOUNDRY_OFFLINE=true
cd <scope-swap-vm>
forge test --use ~/.svm/0.8.30/solc-0.8.30 --match-path 'test/adv/*'      # 18 files, 41 tests, 0 failed
forge test --use ~/.svm/0.8.30/solc-0.8.30 --match-path 'test/adv/AdvIntegration*.t.sol' -vv
```
PoC sources: `test/adv/AdvIntegration{Decode,Extruction,Router}.t.sol` (mirrored in `audit/FINAL_POC/`).
