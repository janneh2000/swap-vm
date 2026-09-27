# FINAL FOURTH-CAMPAIGN ASSESSMENT

**Program:** HackenProof "1inch Aqua" (authorized whitehat research).
**Eligible release under test:** SwapVM **v1.0.2** (`32c687c`), Aqua **v1.0.0** (`81c26e4`),
deployed router **AquaSwapVMRouter → AquaOpcodes**, real **Aqua** ledger.
**Method:** full-spectrum, all-severity, root-cause hunt (not severity-driven). Historical
severity labels were treated as leads, not as safety guarantees.

---

## Verdict

**No novel, in-scope, reachable, reproducible vulnerability was found.**

This holds across four campaigns of increasing depth. Nothing is being manufactured into a
finding. Per the standing directive — *"a real High/Medium is more valuable than a fabricated
Critical"* and *"if nothing survives, say so honestly"* — the honest result is: the eligible
release withstands the attacks in this campaign's map.

## What was actually done this campaign (beyond prior campaigns)

1. **Reduced every audit finding to its root cause** (FULL_AUDIT_ROOT_CAUSE_MAP) and attacked
   the *class/primitive*, not the label.
2. **Attacked the fixes, not the bugs** (FOURTH_CAMPAIGN_POST_FIX_MAP): identified the
   load-bearing assumption behind each fix and tried to violate it from a reachable actor.
3. **Built two new end-to-end PoCs** the prior audits and the repo's own suite lacked:
   - **AdvCanonicalFull** — the *exact deployed program* `[aquaProtocolFee][concentrate][xycSwap]`
     over the real Aqua ledger, asserting wei-exact conservation, register==real, and
     no round-trip profit across **every taker-controlled settlement lever** (direction,
     exactIn/exactOut, isFirstTransferFromTaker, useTransferFromAndAquaPush, `to`, callbacks)
     and fee bps 0..50% — **3000 fuzz runs, green.**
   - **AdvBackwardJump** — empirical proof the interpreter's recompute guards
     (`require(amountIn==0 || amountOut==0)`) defeat backward-`_jump` double-settlement on
     XYCSwap, Fee, and Concentrate, with a green single-settle baseline control.
4. **Ran the repo's own CoreInvariants over the real Aqua path** for compositions the repo only
   tests in sig mode (Pegged, Pegged∘Decay, Pegged∘Fee) — green.
5. **Mapped reachability and authorization** (REACHABILITY_MAP, AUTHORIZATION_MAP, STATE_MODEL)
   to separate *theoretical* code properties from *reachable* attacks.

**Full suite: 15 test files, 34 tests, 0 failures.**

## Why the surface is exhausted for this threat model

Every reachable action by a fully-adversarial **taker** or arbitrary **third party** resolves
to exactly one of three terminal states, none reportable:

- **Revert** — unauthorized program/token (hash binding), backward-jump re-execution
  (recompute guards), foreign `Aqua.pull` (app==msg.sender), non-WETH unwrap.
- **Self-harm** — the actor who chose the action is the only one who loses: a maker griefing
  their own pool or forgoing their own fee revenue; a taker pushing/injecting or unwrapping
  against themselves.
- **Conservative settlement** — value preserved to the wei across {taker, maker, feeTo}, with
  curve rounding directed to the pool, and virtual (Aqua) balances equal to real ERC20 moves.

No path produced: counterparty theft, profitable price-bound escape, double settlement,
invariant (C/L/k) decrease at reachable scale, or virtual/real accounting drift.

## Residual open items (all known, none counterparty-theft)

| Item | Class | Why not a bounty finding |
|------|-------|--------------------------|
| v1.0.2 best-effort fee-skip can forgo protocol revenue | protocol-fee-revenue | Intended v1.0.2 behavior; the entire differential audit set (OZ/Theori/Bailsec/Decurity/MixBytes) rated this Low/Info; emits `ProtocolFeeSkipped`; no counterparty loss |
| Maker can author a losing curve / grief own pool | maker self-harm | Out of any counterparty threat model |
| WETH-unwrap missing `token==WETH` guard (SwapVM.sol:275-278) | robustness (OZ Low, "will resolve") | Non-WETH unwrap reverts → taker self-grief only; no cross-actor impact |
| Wei-level round-trip surplus at absurd (≥~1e25) reserves | benign rounding dust | Non-amplifiable, within OZ-reviewed PeggedSwap tolerance; not reachable at real-value scale (KILL K2-01/K4-12) |

## Honesty statement

This assessment reports the negative result plainly. The attack map, kill ledger, and PoC
matrix are the evidence; the PoCs are runnable and their assertions fire on real settled swaps
(confirmed by ~0.9–1.1M gas averages, not revert-and-return). If a reader wants to extend the
hunt, the highest-value unexplored directions are: (a) integration-level assumptions *outside*
these two contracts (router deployment/config, fee-provider contracts for the dynamic-fee
opcodes, the SDK's program construction), and (b) exotic ERC20 behaviors (fee-on-transfer,
rebasing, non-standard return) interacting with the Aqua pull/push transfers — both of which sit
at or beyond the boundary of the eligible in-scope code and would need explicit scope
confirmation before spending effort.

## Reproduce

```
export PATH="$HOME/.foundry/bin:$PATH"; export FOUNDRY_OFFLINE=true
cd <scope-swap-vm>
forge test --use ~/.svm/0.8.30/solc-0.8.30 --match-path "test/adv/*"
# 15 suites, 34 tests, 0 failed
```
PoC sources: `test/adv/*.t.sol` (mirrored in `audit/FINAL_POC/`).
