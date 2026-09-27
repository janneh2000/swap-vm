# NEW CANDIDATES (second campaign)

No candidate reached Strong/Confirmed. Full fields for the two that produced observable anomalies.

## C2-01 — PeggedSwap round-trip surplus at extreme reserves
ROOT_CAUSE: rounding in PeggedSwapMath at very large normalized values yields a wei-level round-trip
surplus for the taker.
AFFECTED_CODE: src/instructions/PeggedSwap.sol, src/libs/PeggedSwapMath.sol.
ATTACKER_MODEL: unprivileged taker doing exactIn A->B then B->A on the same pegged pool.
PRECONDITION: pool reserves >= ~1e25 base units AND a large single-trade fraction; sane config anchors.
SECURITY_INVARIANT: round-trip must not profit the taker (rounding favors maker).
CONTROL_CASE: reserves <= 1e24 -> round-trip LOSES ~1 wei (maker-favorable). 500 trips @1e24 -> net loss.
MALICIOUS_CASE: reserves 1e27 -> +4 wei; 1e30 -> +4000 wei per round-trip.
OBSERVED_STATE_DELTA / FUND_DELTA: +4 wei (1e27) .. +4000 wei (1e30); ~4e-27 of the pool; NON-amplifiable
(each trip is a few thousand wei, gas >> gain; at realistic scale it is a loss).
WHY EXISTING AUDITS DO NOT COVER IT: n/a — this IS the OZ-reviewed PeggedSwap rounding regime.
WHY NOT A DUPLICATE / IN SCOPE: it is neither novel-impact nor economically material; it is the "simple
rounding / theoretical" class the program excludes.
SEVERITY EVIDENCE: none — no economic impact; wei-dust at non-physical scales.
STATUS: **KILLED** (benign rounding; see SECOND_ORDER_LEDGER K2-01).

## C2-02 — PeggedSwap config-anchor vs shipped-reserve mismatch mispricing
ROOT_CAUSE: PeggedSwap normalizes current reserves by program-encoded anchors (config.x0/y0). If a maker
ships Aqua reserves that differ from those anchors, the invariant is evaluated off-curve -> mispricing /
taker round-trip profit.
AFFECTED_CODE: src/instructions/PeggedSwap.sol (config.x0/y0 vs ctx.swap.balanceIn/Out).
ATTACKER_MODEL: taker on a pool the maker shipped with anchors != reserves.
PRECONDITION: **maker misconfiguration** — config.x0/y0 != shipped (tokens, amounts). The SDK/any sane
maker sets them equal (the strategyHash binds the program incl. these anchors).
OBSERVED: with shipped=(1e9, 5612) but config=(255,64), a round-trip profited the taker (~7.8e9 wei).
WHY NOT IN SCOPE (as a taker vuln): requires a self-harming maker configuration; the taker cannot cause
the mismatch (orderHash binds the program). It is a maker footgun, not an unprivileged-taker attack.
Recommendation to the program: document/validate that PeggedSwap anchors must equal shipped reserves.
STATUS: **MAKER-CONFIG** (out of the taker-attack model; not submitted).

## Everything else attacked → conserved (no candidate):
fee accounting (collect + skip + stacked), settlement matrix (dir×exactIn/Out×ordering×pay-mode),
register==real, cross-order nested callbacks, XYC/Concentrate/Decay/Pegged round-trips, auth binding.
See KILL/SECOND_ORDER ledgers.
