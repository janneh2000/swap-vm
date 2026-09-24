# DUPLICATE LEDGER

Live brief (hackenproof.com) and OpenZeppelin audit page are BOTH egress-blocked in this environment, so the
public findings could not be read verbatim. Known-duplicate context assembled from the task brief + a web
search of the OZ audit summary + the in-code comments.

## Known / audited — DO NOT re-report as-is
- v1.0.2 **Fee update** (best-effort Aqua fee, amountNetPulled): differential audit by Bailsec, Decurity,
  MixBytes, OpenZeppelin, Theori. Code cites OpenZeppelin **M-09** and Theori **#10** directly. (RELEASE_DIFF)
- OpenZeppelin "1inch Aqua and SwapVM MVP v1.0": 3 critical / 2 high / 12 medium / … 53 total. Top finding:
  **PeggedSwap invariant-breaking edge cases → materially incorrect pricing / reserve loss under certain
  parameterizations** (fixed). ⇒ PeggedSwap first-order math is heavily reviewed.
- OZ recommendation: **multi-token integration must undergo a new audit** ⇒ multi-token behaviour (C-03) is
  known-territory, not novel.
- Task-listed known issues: XYC rounding, Decay, TWAP, hook-flag, BaseFeeAdjuster, H1 2026 HackenProof report.

## Novelty firewall result
No candidate reached submission. The reachable-composition candidates (C-01..C-08) are each either the direct
object of an existing audited fix, unreachable on the deployed router, marginal-neutral, or maker-config/
accepted-risk — i.e. they collapse to DUPLICATE / KNOWN-ACCEPTED-RISK / MAKER-CONFIG, none a distinct novel
root cause with unprivileged taker impact.

## Residual (NOT yet cleared against the live brief — verify before any action)
- PeggedSwap **second-order** (a bug introduced by the fix of the OZ PeggedSwap criticals) — highest-value
  un-exhausted frame; requires PeggedSwapMath deep-dive. Cross-check against the actual OZ finding text first.
