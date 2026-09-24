# FOURTH_CAMPAIGN_DUPLICATE_LEDGER

The duplicate firewall. Before anything could be considered novel it had to clear this: is
the mechanism already described by (a) the OZ v1.0 MVP audit, (b) the v1.0.2 differential set
(OZ/Theori/Bailsec/Decurity/MixBytes), or (c) known/standard AMM issues? Because **no
candidate survived the kill ledger**, this document instead certifies that everything examined
maps to a *known* finding or a *non-issue*, i.e. there is nothing left to check for novelty.

---

## Prior-art corpus

- OZ "1inch Aqua and SwapVM MVP v1.0 Audit" — 3 Critical, 2 High, 12 Medium + Low/Notes
  (full text reviewed; see FULL_AUDIT_ROOT_CAUSE_MAP §B).
- v1.0.2 differential reviews (Fee.sol best-effort collection) — OZ, Theori, Bailsec,
  Decurity, MixBytes — all findings Low/Info, protocol-fee-revenue only.
- Standard AMM/DeFi issue classes: sandwich/MEV, rounding-drain, read-only reentrancy,
  first-depositor/inflation, fee-on-transfer token mismatch, donation attacks.

---

## Mechanism → prior art mapping (why nothing is novel-and-open)

| Mechanism examined this campaign | Maps to | Novel? | Open? |
|----------------------------------|---------|--------|-------|
| PeggedSwap C decrease (any param) | OZ C-1, C-3 | No | No (fixed & re-verified) |
| Concentrate L / balance drift under fee | OZ H-1, C-2 | No | No |
| Fee-skip / `amountNetPulled` accounting | v1.0.2 differential (all reviewers) | No | No (intended; Low = protocol revenue) |
| Fee ordering / stacking / decay pre-fee | OZ M-4, M-7, M-10 | No | No |
| Hook/push token injection past bounds | OZ M-8 | No | No (maker-scoped; taker vector = self-loss) |
| `Aqua.push` unrestricted | OZ M-2 | No | No (credit-only) |
| Strategy re-init via ship | OZ M-1 | No | No (maker-scoped) |
| Calldata.slice underflow | OZ M-3 | No | No |
| Sig-mode loose binding | OZ M-6 | No | No (order hash binds program) |
| WETH unwrap missing token==WETH | OZ Low ("will resolve") | No | Known-Low; self-grief only |
| Quote vs swap divergence | OZ M-12 | No | No (swap enforces sufficiency) |
| Backward-jump re-execution | Standard interpreter safety; guarded by design | No mechanism (reverts) | No |
| Full-program composition conservation | (new *test* coverage, not a new bug) | Test is new; result is "no bug" | N/A |
| Taker-lever settlement matrix | (new test coverage) | Test is new; result is "no bug" | N/A |
| Round-trip at realistic scale | Standard rounding-drain class | No | No |

---

## The two genuinely new *tests* (not new bugs)

The fourth campaign added coverage the prior audits/repo did not have:

1. **AdvCanonicalFull** — end-to-end conservation + round-trip on the *exact deployed program
   shape* over the real Aqua ledger under all taker levers.
2. **AdvBackwardJump** — empirical proof the interpreter's recompute guards defeat backward-jump
   double-settlement.

Both **confirm robustness**. Neither reveals a mechanism absent from prior art. There is
therefore no candidate to run a novelty/duplicate decision on — the firewall has nothing to
reject and nothing to pass through.

## Verdict

No novel, in-scope, open finding exists to deduplicate. Should any future mechanism be found,
it must be checked against the corpus above before being treated as novel.
