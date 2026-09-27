# POC MATRIX

Foundry (forge/anvil) is NOT installed in this sandbox and the scoped repo is Foundry-first, so PoCs are
authored to run on the user's machine (`forge test` in a clone of scope-swap-vm@v1.0.2 with `forge install`).
No candidate reached CONFIRMED, so no exploit PoC is shipped. Control/observation harnesses that would
EMPIRICALLY confirm the kills (defense-verification PoCs) are outlined for hand-off:

| ID | What a PoC would show | Type | Status |
|----|-----------------------|------|--------|
| C-01 | taker cannot underpay: no-push/short-push revert; only real push satisfies | control | analytically KILLED; test would confirm (mirrors TakerCallbackAquaNegative.t.sol) |
| C-03 | 3-token XYC cycle A→B→C→A nets ≤ 0 for the taker | control | analytically KILLED (marginal-neutral); test would confirm |
| C-04 | `[Fee][Invalidator][curve]` caps at gross; wrong order is maker footgun | control | not reachable on live router |
| K-04 | both transfer orderings → identical balances for identical signed intent | A/B | analytically KILLED |

No MALICIOUS-case PoC exists because no invariant break was found. Per campaign rules, this hunt's output is
a **documented anti-pattern set** (the defenses in INVARIANTS.md / KILL_LEDGER.md), not a finding.
