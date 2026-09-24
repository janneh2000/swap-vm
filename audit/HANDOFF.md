# HANDOFF

## Status
Thorough, multi-frame offensive review of the LIVE in-scope target — **AquaSwapVMRouter** (the only deployed
SwapVM router, per broadcast/) + **Aqua/AquaRouter** — at the eligible releases (SwapVM v1.0.2 32c687c, Aqua
v1.0.0 81c26e4, both cloned to /home/user/scope-*). **No confirmed, novel, unprivileged-taker-exploitable
bug found.** The SwapVM↔Aqua composition is robustly engineered and consistent with 6-firm + differential
audit history.

## What was covered (all 8 specialist frames + hidden-assumption loop)
Serialization/orderHash binding · sig-vs-Aqua auth separation · opcode dispatch & table drift · VM registers &
nested runLoop · settlement/temporal (both transfer orderings) · Aqua ledger isolation & the amountNetPulled
sufficiency check · v1.0.1→v1.0.2 differential (Fee.sol only) · second-order of the fee fix · Multicall/
Simulator/TransientLock/Calldata.slice primitives. See KILL_LEDGER.md (12 kills) and ASSUMPTION_LEDGER.md.

## Environment limitations to resolve for the next pass
1. **Egress blocks** hackenproof.com and openzeppelin.com → the live brief (scope/OOS/severity floor/known
   issues) and the full OZ/Theori/MixBytes finding texts were NOT read verbatim. Get these to (a) finalize
   the duplicate ledger and (b) run Specialist-8 on the *exact* fixed findings.
2. **No Foundry** in-sandbox → PoCs must run on the user's machine.

## Highest-value un-exhausted frame (recommended next)
**PeggedSwap second-order** (AquaOpcodes op31, on the live router; `PeggedSwapMath.sol` + `Power.sol` NOT yet
read in depth). OZ's top finding was PeggedSwap invariant-breaking pricing/reserve-loss; a defect introduced
by that FIX, or a residual edge at the price-range boundary interacting with Aqua real-balance caps, is the
most promising place a novel, in-scope, PoC-able bug could still live. Must first diff against the exact OZ
PeggedSwap finding to avoid a duplicate.

## Secondary residual frames
- XYCConcentrate boundary math (op18) vs Aqua real-balance cap (register inflation) — precision/rounding at
  sqrtPrice bounds; cross-check ConcentrateXYCRounding.t.sol.
- Decay offset accumulation edge (uint216 saturation) under extreme maker balances.
- If a full SwapVMRouter is ALSO deployed elsewhere (not seen in broadcast/), the sig-mode full-opcode surface
  (Balances/Invalidators/DutchAuction/rate-adjusters/TWAP) reopens C-02/C-04 — verify deployment.
