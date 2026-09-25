# STBL_PREVIOUS_REPORT_DUPLICATES — hard duplicate firewall (our two prior submissions)

Source: user-supplied HackenProof dashboard screenshot (2026-09-25). Both marked **Duplicate**.
These two ROOT CAUSES are excluded. A candidate that shares either root cause — regardless of
different function name, address, asset, amount, or PoC shape — is a DUPLICATE and must be killed.

## DUP-1 — STBLSCBB-387 (05.09.2026, Duplicate, severity None/0$)
**Title:** "STBL — Yield distribution is not time-weighted: a just-in-time depositor captures a
full period's [yield]…"
**Root cause (as understood):** the YieldDistributor allocates a distribution across current
holders/positions **without weighting by time-in-position**, so an attacker who deposits/mints
immediately before a `distribute`/checkpoint captures a full period's yield they did not earn
(JIT yield capture / MEV around distribution timing).
**Excluded primitive:** JIT deposit → capture undeserved yield due to missing time-weighting in
YieldDistributor distribution/accrual. Any variant (PT or LT distributor, USDY or OUSG, deposit
vs transfer-in, front-run vs same-block) is the SAME root cause → duplicate.

## DUP-2 — STBLSCBB-386 (05.09.2026, Duplicate, severity None/0$)
**Title:** "STBL — LT1_Issuer.withdrawExpired() seizes an expired position's collateral to the
Treasury but…" (truncated)
**Root cause (as understood):** `LT1_Issuer.withdrawExpired()` moves an expired position's
collateral to the Treasury but mishandles the associated accounting/claim (the truncation hides
the exact consequence — likely the position/claim is not fully cleared, or the user's residual
entitlement is lost/duplicated, or supply/backing is left inconsistent).
**Excluded primitive:** the collateral-seizure-on-expiry path in `LT1_Issuer.withdrawExpired()`
and its Treasury transfer + associated accounting. Any variant on THAT function's expiry-seizure
behavior is the SAME root cause → duplicate.
**Note:** other bugs in `LT1_Issuer` with a *different* root cause and function are NOT excluded
by this — only the withdrawExpired expiry-seizure primitive is.

## Firewall rule
Novelty requires a genuinely different: ROOT CAUSE **or** SECURITY INVARIANT **or** ATTACKER
CAPABILITY **or** STATE TRANSITION **or** ECONOMIC CONSEQUENCE — vs both DUP-1 and DUP-2 AND vs
the public Cyfrin STBL / ESS-Redemptions findings. A new address/function/asset/amount/PoC alone
is NOT novelty.

⚠️ We CANNOT see private HackenProof submissions. Language stays "not a duplicate of the supplied
references + public audits," never "guaranteed unsubmitted by another researcher."
