# SEMANTIC BOUNDARIES (Representation & Semantic-Divergence chain)

SOURCE (off-chain order) → MUG/TRAITS encoding → orderHash → auth → program bytes → opcode decode →
registers → validate → hooks/callbacks → token/Aqua ops → settlement → (rollback).

Per-transition resolution (all PROVEN consistent for the live target):
1. Same value read twice? balanceIn/Out read once via safeBalances; re-read of tokenIn bucket at the
   sufficiency check is intentional (post-settlement). originalAquaBalanceIn is a fixed snapshot.
2. Value change between validation and consumption? tokenIn/tokenOut/amount fixed from calldata for the whole
   swap; program fixed by orderHash binding.
3. X validated but Y consumed? safeBalances validates the SAME (tokenIn,tokenOut) the registers/curve/
   settlement use.
4. Mutable component in the final value uncovered by the original assumption? amountNetPulled is the only
   register that gates settlement and is bound to real fee pulls (atomic).
5. Attacker-controlled input changes object classification? tokenIn/tokenOut are taker-chosen but constrained
   by safeBalances(active-strategy) + validate(tokenIn!=tokenOut). Curve prices generically per (balanceIn,
   balanceOut) → direction choice is legitimate.
6. Rollback restores all state? try/catch fee pull rolls back atomically; a reverted swap rolls back
   registers + transient lock.
7. One success overwrites a prior failed invariant? No — checks are conjunctive (require), not overwritten.
8. Identity/domain bindings end-to-end? maker (ship msg.sender ↔ order.maker via orderHash), app (=router in
   pull/push/safeBalances), token (safeBalances↔curve↔settlement), chainId (sig domain; Aqua per-chain ship),
   orderHash (=strategyHash). All preserved.
9. Quoted == settled? amounts identical (fee pricing is context-independent); documented divergences are
   state-write-only, not amount-affecting.
10. Value conservation across lifecycle? maker Δ = (+amountIn −fee_in) tokenIn, (−amountOut −fee_out) tokenOut;
    taker Δ = (−amountIn) tokenIn, (+amountOut) tokenOut; fee recipient = +fee. Conserved.

Differentials examined: sig-path vs Aqua-path settlement (I15); v1.0.1 vs v1.0.2 (RELEASE_DIFF); view/quote vs
swap (I12); success vs rollback (item 6); direct call vs callback/nested (K-02/K-04). No exploitable divergence.
