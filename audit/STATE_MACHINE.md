# STATE MACHINE

## Aqua bucket lifecycle (per maker,app,strategyHash,token)
UNSHIPPED (count=0, bal=0)
  --ship-->            ACTIVE (count=N, bal=amount)         [ship: count must be 0]
ACTIVE --pull(app=router)-->  ACTIVE (bal-=amt) [underflow-revert if amt>bal]
ACTIVE --push(app=param)-->   ACTIVE (bal+=amt) [requires ACTIVE]
ACTIVE --dock(all N tokens)--> DOCKED (count=0xFF, bal=0)
DOCKED: push reverts (not active); pull reverts (bal 0 → underflow); ship reverts (count!=0) → TERMINAL.
Reachable-but-unintended states probed: re-ship after dock (blocked, count=0xFF); multi-ship same hash with
disjoint token sets (possible, but pairwise-XYC is arbitrage-neutral — C-03); partial dock (blocked).

## SwapVM swap() control flow
lock(orderHash)
 → parse takerTraits; build Context (registers fresh; amountNetPulled=0)
 → [Aqua] safeBalances → balanceIn/Out ;  [sig] verify signature
 → snapshot originalAquaBalanceIn
 → runLoop(program): [op][len][args]* ; wrappers (Fee, Decay, XYCConcentrate) nest via ctx.runLoop();
     fee-in pulls maker tokenIn mid-loop (best-effort) → amountNetPulled
 → order.traits.validate(tokenIn,tokenOut,amountIn)   [tokenIn!=tokenOut; zero-amount rule]
 → takerTraits.validate(amount,amountIn,amountOut)     [exact match + threshold + deadline]
 → transfer phase, ORDER chosen by taker isFirstTransferFromTaker:
     transferOut: preOutHook, preOutCallback, PULL tokenOut(maker→to), postOutHook
     transferIn : preInHook, preInCallback(taker pushes tokenIn), [Aqua] push-or-check, postInHook
 → unlock(orderHash) ; emit Swapped
Both transfer orderings verified to yield identical final accounting (see KILL_LEDGER K-04).

## quote() = swap() runLoop + validate in isStaticContext=true; NO transfer phase, NO sufficiency check;
all state writes suppressed. Returns (amountIn, amountOut, orderHash).
