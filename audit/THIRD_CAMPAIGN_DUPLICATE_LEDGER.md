# THIRD CAMPAIGN DUPLICATE LEDGER

Full audit archive in hand (8 firms v1 + 5 firms v1.0.2). Cross-checked every candidate root-cause:
- All Critical/High root causes (PeggedSwap precision + axis, XYCConcentrate multi-token/state, fee
  accounting) were found by multiple firms and FIXED in v1.0.2; my tests confirm the fixes hold, so there
  is no un-fixed instance to report.
- All live/acknowledged findings (hook injection, Calldata.slice, unrestricted push, fee-on-fee, fee
  revert on maker shortfall, Extruction, Decay griefing, ship reinit, maker-hook subsidy, fee-token
  blocklist) are documented accepted risks / maker-config / DoS / fee-revenue-loss — already reported by
  the auditors and acknowledged by the team. Re-reporting any would be a DUPLICATE.
- No distinct, novel root cause with a new unprivileged-taker capability was discovered.

Nothing to submit.
