# RELEASE DIFF — v1.0.1 → v1.0.2 (SwapVM)

## The entire delta is `src/instructions/Fee.sol`
`git diff v1.0.1(b6e4f97) v1.0.2(32c687c) -- src/` → **1 file changed, 63 insertions, 18 deletions**, all in `Fee.sol`.
Every other in-scope file is byte-identical to v1.0.1 (audited by OpenZeppelin + the v1.0.1 review).

## What changed (the "Fee update" that Bailsec/Decurity/MixBytes/OpenZeppelin/Theori differentially audited)
The Aqua protocol-fee-on-input pull became **best-effort** instead of mandatory:

- Added `event ProtocolFeeSkipped(orderHash, token, to, amount)`.
- `_aquaProtocolFeeAmountInXD` / `_aquaDynamicProtocolFeeAmountInXD`:
  - Added a zero-recipient guard: `if (feeBps != 0) require(to != address(0))`.
  - Replaced the unconditional `_AQUA.pull(...)` + unconditional `amountNetPulled += feeAmountIn`
    with `_tryPullFee(ctx, to, feeAmountIn)`.
- New `_tryPullFee`: `try _AQUA.pull(...) { amountNetPulled += feeAmountIn; } catch { emit ProtocolFeeSkipped; }`
  - Credits `amountNetPulled` **only when the pull lands** (atomic — an external-call revert rolls back the
    balance decrement AND the token transfer together).
  - Fixes OpenZeppelin **M-09** / Theori **#10**: a maker who couldn't cover the fee previously made a
    one-sided position untradable / capped a two-sided one; now the swap proceeds fee-free and the maker
    keeps the uncollected fee (ACCEPTED RISK, monitored via `ProtocolFeeSkipped`).

## Second-order analysis of the change (Specialist 8 target)
- The try/catch is **atomic**: no partial state where `amountNetPulled` is credited without the maker's
  balance/tokens moving, and none where the maker's balance moved without the credit. → `amountNetPulled`
  stays exactly equal to the tokenIn actually removed from the maker ledger.
- The fee outcome is **taker-neutral**: collected vs skipped yields identical `amountIn`/`amountOut` for the
  taker (pricing via `_feeAmountIn` is unchanged either way). Only the fee-recipient (loses) and maker
  (keeps) are affected. A taker cannot profit from, nor is harmed by, forcing a skip; the skip trigger is
  the maker's own balance/allowance, not taker-controllable to the taker's benefit.
- The sufficiency check `balanceIn >= originalAquaBalanceIn + amountIn - amountNetPulled` cannot underflow:
  a single input fee is `feeBps/BPS ≤ 1` of amountIn (exactIn restores full amountIn; exactOut grows it),
  so `amountNetPulled < amountIn(final)` and RHS ≥ originalAquaBalanceIn ≥ 0.
- The parameterless `catch` deliberately swallows both Aqua's underflow Panic and the token-leg revert, and
  avoids copying attacker-inflatable revert data. No OOG-swallow escalation found (caller controls gas; a
  malicious tokenIn must be a maker-shipped token, so not taker-injectable).

## Scope consequence
The novel code is exactly the differentially-audited Fee change → **not a primary target** (duplicate
pressure). The hunt therefore targeted the *composition* of this change with the (v1.0.1, separately-audited)
rest — see CANDIDATES.md / KILL_LEDGER.md.
