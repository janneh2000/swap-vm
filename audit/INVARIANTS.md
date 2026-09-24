# INVARIANTS (live target: AquaSwapVMRouter + Aqua)

## Aqua ledger (verified PROVEN, Aqua.sol)
I1. Balance buckets are isolated by (maker, app, strategyHash, token). Only ship(init once), dock(clear),
    pull(app=msg.sender, decrement), push(app=param, increment, requires active) touch a bucket.
I2. Aqua holds NO tokens: pull = safeTransferFrom(maker→to)+decrement; push = safeTransferFrom(pusher→maker)+
    increment. A bucket is an allowance the maker grants an app to pull from the maker's wallet.
I3. push requires an ACTIVE strategy (tokensCount>0 && !=0xFF) → an attacker cannot credit an arbitrary
    bucket; only the maker can activate a bucket (ship, msg.sender=maker). ⇒ no cross-bucket value movement
    except via the maker's real wallet (a hard, shared cap).
I4. pull relies on uint248 underflow to bound to bucket balance (no explicit active check) — safe because a
    never-shipped/docked bucket has balance 0 → pull(>0) reverts.
I5. strategyHash = keccak256(strategy); ship stores the same tokensCount for every token of the strategy;
    dock requires closing exactly all tokensCount tokens.

## SwapVM ↔ Aqua composition (verified PROVEN, SwapVM.sol)
I6. Aqua orderHash = keccak256(abi.encode(order)) == the shipped strategyHash; app = router. Binds the whole
    order (maker,traits,data incl. program) to the Aqua bucket. A mismatch → safeBalances reverts (self-DoS).
I7. tokenIn sufficiency: after settlement, maker tokenIn bucket ≥ originalAquaBalanceIn + amountIn −
    amountNetPulled ⇔ taker delivered ≥ amountIn net of maker-authorized fee. Cannot be satisfied without the
    taker paying (donations are net-negative; taker cannot pull tokenIn back). Cannot underflow.
I8. amountNetPulled == tokenIn actually removed from the maker ledger by landed fee pulls (atomic try/catch).
I9. tokenOut settlement pulls exactly amountOut (+ maker-set fee-out, not on live router) from the maker's
    real bucket; register balanceOut (≥ curve output) ≤ real bucket at snapshot ⇒ pull cannot over-extract
    (over-inflation → underflow revert = DoS, never theft).
I10. Registers are fresh per swap (Context re-init). No cross-swap register contamination.
I11. Reentrancy guard per orderHash held across all hooks/callbacks; blocks same-order re-entry. Cross-order/
     cross-app nesting is bounded by per-strategyHash isolation (I1) + the shared real-wallet cap.
I12. Every state-writing opcode guards on `!isStaticContext` ⇒ quote() (non-view, static flag) mutates nothing.

## Curve / pricing (documented, audited — not primary target)
I13. Rounding favors the maker: amountIn ceilDiv (up), amountOut floor (down). (XYCSwap, LimitSwap, PeggedSwap.)
I14. XYCSwap/PeggedSwap require both balances > 0; exactOut reverts if amountOut ≥ balanceOut (balance
     sufficiency). Decay only shrinks register balanceOut / grows balanceIn (worse for taker; never over-pull).

## Auth-context separation (verified PROVEN)
I15. sig-mode orderHash (EIP-712 digest, domain=name/version/chainId/router) vs Aqua-mode orderHash
     (keccak256(abi.encode(order))) cannot collide; mode fixed by a traits bit that is inside both hashes.
     Router binding: sig via EIP-712 verifyingContract; Aqua via ship's app. Multi-router execution of one
     order needs the maker to ship/sign to multiple routers (self-inflicted).
