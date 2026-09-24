# AUDIT ASSUMPTION ATTACK MAP

> ⚠️ BLOCKER: The audit PDF referenced in the campaign brief **was not present in the container**.
> `/home/user/attach` and `/home/user/user-data` are empty; only the two whitepapers
> (`docs/whitepaper-{swap-vm-1.0,aqua-1.0}.pdf`) are on disk. hackenproof.com and openzeppelin.com are
> egress-blocked, so the exact finding wording could not be fetched either. This map is therefore built
> from: (a) the whitepapers (extracted to `/home/user/wp_swapvm.txt`, `wp_aqua.txt`), (b) in-code comments
> that cite specific findings, and (c) a web-search summary of the OZ audit. **Re-attach the PDF (or paste
> the findings) to complete the exact Specialist-A/B/D/F pass.**

## Known findings (from code comments + web summary; NOT the verbatim PDF)
| ID | title (as known) | affected | remediation (as-shipped in v1.0.2) | assumption the fix relies on | 2nd-order attacked? | status |
|----|------|----------|------------------------------------|------------------------------|---------------------|--------|
| OZ M-09 / Theori #10 | Aqua protocol-fee pull can make a position untradable / cap it | Fee.sol `_aquaProtocolFeeAmountInXD` | best-effort `_tryPullFee` (try/catch); credit `amountNetPulled` only on landed atomic pull; skip+event otherwise | try/catch is atomic; amountNetPulled == real ledger pull; taker-neutral | YES (campaign 2 + 3): conservation across matrix + skip path + stacked; register==real. HOLDS | KILLED (robust) |
| OZ (Critical, per web summary) | PeggedSwap invariant-breaking pricing / reserve-loss under certain parameterizations | PeggedSwap.sol / PeggedSwapMath.sol | maker-favorable rounding (amountOut floor, amountIn ceil; y1/x1 ceil), numeric-stability rationalization in solve(), documented bounds (u<=~4*ONE, x<=1e30) | reserves stay within documented bounds; config anchors == shipped reserves | YES: realistic-scale round-trips maker-favorable (8000 runs); repo invariant suite passes on Pegged/Pegged+Decay/Pegged+Fee in real Aqua mode | KILLED / not novel |
| OZ (per web summary) | exact-out rounding behavior | PeggedSwap exactOut | ceil on amountIn | exactOut rounds toward maker | YES: exactOut in conservation + symmetry checks | HOLDS |
| OZ (per web summary) | token-binding / multi-token concerns; "multi-token integration needs a new audit" | curves + Aqua safeBalances (any pair in an N-token strategy) | documented caveat (not a code fix) | makers use 2-token strategies / SDK sets anchors == reserves | multi-token XYC = marginal-arbitrage-neutral (campaign 1); Pegged anchor-mismatch = maker-config only | out-of-model (maker-config) |
| v1.0.2 differential (Bailsec/Decurity/MixBytes/OZ/Theori) | the Fee "best-effort" change itself | Fee.sol | as above | as above | YES | KILLED |

## What the whitepaper documents as load-bearing assumptions (attack targets)
- 7 core invariants (symmetry, additivity subadditive, quote/swap consistency, monotonicity,
  rounding-favors-maker, balance-sufficiency, liveness) — all validated empirically incl. on untested
  Aqua-mode compositions (test/adv/AdvInvariantsAqua.t.sol). HOLD.
- Canonical Aqua order `aquaProtocolFee -> [concentrate] -> flatFee -> xycSwap -> salt`; conservation law
  `pool balance + protocol fee = initial balance + total amountIn`. Verified (conservation fuzz). HOLDS.
- Aqua **no-custody**: maker tokens never leave the maker wallet; Aqua tracks allowances only ⇒ a bricked
  strategy is NOT a fund lock (maker docks + reships). So liveness breaks are griefing at most, not Critical.
- amountNetPulled documented as "used by fee AND accounting instructions" (plural) — on the LIVE
  AquaOpcodes router only Fee writes it; no other accounting instruction exists there.

## Requirement to finish this campaign as designed
Provide the audit PDF(s). Then Specialist A/B/D/F re-run against the EXACT findings: for each, reconstruct
exploit+fix, extract the introduced assumption, and attack it (many are pre-attacked above, but the PDF may
reveal Medium/Low findings and design caveats not visible from code comments).
