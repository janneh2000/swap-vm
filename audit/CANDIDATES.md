# CANDIDATES

Live target = **AquaSwapVMRouter** (only router deployed, CREATE3 deterministic addr, per broadcast/) +
**Aqua/AquaRouter**. Reachable instruction set = AquaOpcodes: Controls (jumps/guards/salt/deadline),
XYCSwap, XYCConcentrate, Decay, Fee(input variants), PeggedSwap, Extruction. Two auth modes (sig / Aqua),
but sig mode is impractical on this router (no Balances instruction to set reserves), so the live surface is
effectively Aqua-mode.

Status legend: KILLED / DUPLICATE / KNOWN-ACCEPTED-RISK / MAKER-CONFIG (out of taker's control) /
INCONCLUSIVE / STRONG-CANDIDATE / CONFIRMED. No candidate reached STRONG-CANDIDATE or CONFIRMED.

---

## C-01 — Aqua tokenIn sufficiency check gamed to underpay the maker
ID: C-01
STATUS: KILLED
ROOT_CAUSE (hyp): `SwapVM._transferIn` uses an absolute snapshot check `rawBalances(maker,router,orderHash,tokenIn) >= originalAquaBalanceIn + amountIn - amountNetPulled` (SwapVM.sol:239-240).
AFFECTED_RELEASE: v1.0.2
AFFECTED_CODE: SwapVM.sol:200,239-240; Aqua.sol push/pull.
SECURITY_INVARIANT: taker must deliver ≥ amountIn tokenIn (net of maker-authorized fee) to the maker's Aqua bucket.
AUTHORIZATION_MODEL: Aqua (safeBalances active-strategy).
ATTACKER_CONTROL: taker callbacks, transfer ordering, useTransferFromAndAquaPush, nested swaps on other orders.
OBSERVED_RESULT: check rearranges to `(pushes) − (non-fee pulls) ≥ amountIn`. Only a push raises the slot;
push moves tokens FROM the pusher; a third-party donation is net-negative for the attacker group; the taker
cannot pull tokenIn back (pull's app = msg.sender = router, not taker). Cross-order nesting hits a different
strategyHash slot (isolated). `amountNetPulled` is only creditable by a landed maker fee-pull that actually
reduced the same slot. No underpayment path.
WHY_NOT_KNOWN: this is the direct object of the audited fee change; re-derived, holds. Negative tests cover
no-push/insufficient/one-wei-short/wrong-hash (TakerCallbackAquaNegative.t.sol).
FALSIFICATION: attempted third-party push (net-negative), cross-order push (wrong slot), fee-to-taker
(maker-controlled `to`), useTransferFromAndAquaPush vs default (identical result). All fail.

## C-02 — Register↔real balance divergence (DynamicBalances/StaticBalances overriding Aqua-loaded balances)
ID: C-02
STATUS: KILLED (not reachable on live router)
ROOT_CAUSE (hyp): Balances instructions overwrite Aqua-loaded ctx.swap.balanceIn/Out; curve prices on
overwritten values while settlement pulls real Aqua balances.
AFFECTED_CODE: Balances.sol (Static/Dynamic).
OBSERVED_RESULT: `Balances._{static,dynamic}BalancesXD` are NOT in AquaOpcodes → unreachable on the deployed
AquaSwapVMRouter. StaticBalances also `require(balanceIn==0 && balanceOut==0)` which reverts once Aqua
pre-loads a non-zero balance. Even if reachable, over-stated balanceOut → pull underflow (DoS, capped at
real), never over-extraction. Documented ("drop DynamicBalances for Aqua"). MAKER-CONFIG.
WHY_NOT_KNOWN: N/A — not reachable.

## C-03 — Token-agnostic orderHash + multi-token strategy cross-pair arbitrage
ID: C-03
STATUS: KILLED (marginal-neutral) + DUPLICATE (multi-token flagged by OZ audit)
ROOT_CAUSE (hyp): a tokenless XYC program's orderHash = keccak256(abi.encode(order)) does not bind the token
set; a maker can ship ≥3 tokens under one strategyHash; safeBalances admits any pair; XYCSwap prices any pair
pairwise as x·y=k on shared balances.
OBSERVED_RESULT: pairwise constant-product on SHARED balances is marginal-arbitrage-neutral (product of
cyclic marginal prices B/A·C/B·A/C = 1); any finite cycle loses to slippage. No taker profit. Requires the
maker to ship a multi-token XYC strategy — MAKER-CONFIG. OZ audit explicitly flags multi-token integration as
requiring a new audit → DUPLICATE/known-territory.
FALSIFICATION: cyclic-arbitrage model → net ≤ 0.

## C-04 — Invalidator↔fee instruction-ordering over-fill
ID: C-04
STATUS: KILLED (not reachable) + MAKER-CONFIG (documented)
ROOT_CAUSE (hyp): `[Invalidator][Fee][curve]` records the fee-adjusted amount (net) while settlement moves the
gross, letting cumulative fills exceed the cap.
OBSERVED_RESULT: Invalidators are NOT in AquaOpcodes → unreachable on the live router. Even in signature mode
(full router, not deployed), the correct ordering `[Fee][Invalidator][curve]` records gross and is
consistent; the wrong ordering is a documented "instruction order is security-critical" maker footgun.
MAKER-CONFIG.

## C-05 — quote() non-view / state-mutation without a swap
ID: C-05
STATUS: KILLED
ROOT_CAUSE (hyp): `SwapVM.quote` is declared non-`view` and hardcodes isStaticContext=true; a directly-called
quote could mutate state if an instruction failed to guard on isStaticContext.
OBSERVED_RESULT: every VM-opcode state write (Fee pulls, DynamicBalances, Decay offsets, Invalidators, TWAP)
is guarded by `if (!ctx.vm.isStaticContext)`. Extruction routes to IStaticExtruction (view) in static mode.
No unguarded write. No nonce-burn / fill-mutation via quote.

## C-06 — Calldata.slice missing `begin<=end` bound → giant slice
ID: C-06
STATUS: KILLED (self-harm only)
ROOT_CAUSE: `Calldata.slice(begin,end,exc)` checks only `end>length`, not `begin<=end`; `begin>end` underflows
res.length to ~2²⁵⁶ (solidity-utils 6.9.7 Calldata.sol:34-45).
OBSERVED_RESULT: all callers' offsets are either maker-bound (signed / abi.encode(order) shipped → self-harm
OOG) or the taker's own takerData slices (self-harm / no-impact: giant `to`→defaults to taker, giant
`threshold`→disables own slippage, giant `signature`→sig fails). No cross-party impact; offsets are never
attacker-controlled for another party's value.

## C-07 — Extruction register/PC rewrite
ID: C-07
STATUS: MAKER-CONFIG (documented "use at your own risk")
ROOT_CAUSE: Extruction delegates all registers + nextPC to a maker-chosen external contract (regular call in
swap mode); SwapVM trusts the returned SwapRegisters (incl. amountNetPulled).
OBSERVED_RESULT: target is program-controlled (maker), called as itself (not delegatecall — cannot act as the
router). A malicious maker can misprice/grief takers (mitigated by taker threshold/slippage). Taker only
influences the target via instructionsArgs; abusing that is the maker target's bug, not the protocol's.

## C-08 — Best-effort fee skip griefing / taker-forced skip
ID: C-08
STATUS: KNOWN-ACCEPTED-RISK
ROOT_CAUSE: v1.0.2 makes the Aqua input fee best-effort; an uncollected fee stays with the maker.
OBSERVED_RESULT: taker-neutral (see RELEASE_DIFF.md). Only fee-recipient revenue is at risk, controlled by
the maker's own balance — the documented ACCEPTED RISK, monitored via ProtocolFeeSkipped.
