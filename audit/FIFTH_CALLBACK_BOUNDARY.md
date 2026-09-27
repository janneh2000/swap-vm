# FIFTH_CALLBACK_BOUNDARY

Phase 9 — the callback/integration boundary, looking specifically for **stale-snapshot** bugs
(component reads state A, a callback mutates A, another component trusts the old value) rather
than ordinary reentrancy (covered in campaigns 1–4).

## The external-call surface during a swap

| Call site | Who runs | Type | Order relative to settlement |
|-----------|----------|------|------------------------------|
| maker pre/postTransferIn/Out hooks | maker's target | CALL | around the in/out transfers |
| taker preTransferInCallback | taker | CALL | in `_transferIn`, before the sufficiency check |
| taker preTransferOutCallback | taker | CALL | in `_transferOut`, before the pull |
| dynamic fee provider | maker's provider | STATICCALL | inside runLoop |
| Extruction target | maker's target | CALL (IExtruction) | inside runLoop |
| token transfer hooks (ERC777) | token | CALL | during push/pull |

## Snapshot analysis — is any value read, then mutated by a callback, then trusted?

The candidate stale value is the **Aqua balance** used by the sufficiency check:
`require(balanceIn >= originalAquaBalanceIn + amountIn − amountNetPulled)` (SwapVM.sol:240).

- `originalAquaBalanceIn` is snapshotted **before** runLoop (`ctx.swap.balanceIn` after
  `safeBalances`, SwapVM.sol:200). Between the snapshot and the check, callbacks run.
- The check **re-reads** `balanceIn` live from Aqua at the moment of the check
  (`AQUA.rawBalances(...)`, :239) and compares to the snapshot + amountIn − amountNetPulled. So it
  is a *fresh* read compared against a *fixed* baseline. A callback that changes the maker's Aqua
  balance is **accounted for**: the taker must have pushed enough that live ≥ baseline + owed.
- **Attempt: taker inflates balanceIn via `push` in preTransferInCallback to pass the check
  cheaply.** `push` credits the maker but transfers the tokens FROM THE TAKER; the taker cannot
  push value they don't send. Proven pure-loss in AdvConcentrateHook (campaign 4).
- **Attempt: taker `push`es tokenOut in preTransferOutCallback to survive an over-large pull.**
  Same — the pushed tokenOut is the taker's, credited to the maker; the pull returns only
  `amountOut`; net taker loss (AdvConcentrateHook). No stale-snapshot gain.

The `amountNetPulled` term is the only other moving piece: it is incremented **only** when a fee
pull actually lands (`_tryPullFee`), inside the same runLoop, before the check — never from a
callback. So the check's inputs are either fixed-baseline, freshly-read, or in-loop-consistent.
**No stale snapshot is trusted.**

## Extruction as a callback (the strongest lever)

`Extruction` does a state-changing CALL to a maker-chosen target that then **replaces the entire
SwapRegisters**. Even so:
- It cannot conjure funds: settlement still `AQUA.pull`s from the maker, bounded by the maker's
  balance → over-large amountOut reverts (AdvIntegrationExtruction.test_extruction_cannot_conjure_funds).
- It cannot force the taker to overpay: `TakerTraits.validate` binds the taker's declared exactIn
  amount to `amountIn` (AdvIntegrationExtruction.test_extruction_cannot_force_taker_overpay).
- A within-balance forced settlement still conserves real==virtual and touches only this maker
  (AdvIntegrationExtruction.test_extruction_within_balance_conserves).
- Cross-order reentry from the target hits a *different* orderHash lock, i.e. just a normal
  independent swap — no privilege gain (AdvNested, campaign 4).

## Reentrancy recap (not the focus, but confirmed)

Per-orderHash **transient** lock (`_reentrancyGuards[orderHash]`) blocks same-order reentry.
Aqua push/pull are CEI. ETH from WETH-unwrap goes to the taker's `to`, not the router;
`OnlyWethReceiver` restricts inbound ETH to WETH. No compounding on a single order.

## Verdict

No stale-snapshot / read-then-mutate-then-trust primitive exists across the callback boundary.
The sufficiency check re-reads live balances against a fixed baseline; every callback-reachable
mutation is either paid for by the actor (push = donation) or bounded by the maker's own balance
and the taker's own amount/threshold binding. CANDIDATES C5-06 (KILLED).
