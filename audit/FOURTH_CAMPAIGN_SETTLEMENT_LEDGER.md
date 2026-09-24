# FOURTH_CAMPAIGN_SETTLEMENT_LEDGER

The exact token-flow accounting of a SwapVM/Aqua settlement, with every branch of the
settlement code, and the conservation identity each branch must satisfy (RC-3/RC-8). Derived
from `SwapVM.sol:_transferIn / _transferOut / _transferFrom / _transferOrPull` (lines 217–283).

---

## 1. The settlement branches

### tokenIn (maker receives), Aqua mode (`useAquaInsteadOfSignature == true`)

Two taker-selected sub-paths:

- **A. push path** (`useTransferFromAndAquaPush == true`), SwapVM.sol:234–237:
  ```
  IERC20(tokenIn).safeTransferFrom(taker, router, amountIn)
  IERC20(tokenIn).forceApprove(AQUA, amountIn)
  AQUA.push(maker, router, orderHash, tokenIn, amountIn)   // real: router→maker; virtual: +amountIn
  ```
- **B. check path** (`useTransferFromAndAquaPush == false`), SwapVM.sol:239–240:
  the taker is expected to have `push`ed tokenIn during `preTransferInCallback`; the router only
  verifies:
  ```
  require(balanceIn >= originalAquaBalanceIn + amountIn − amountNetPulled)
  ```

`amountNetPulled` is the amount already pulled from the maker earlier in the program (e.g. an
Aqua protocol fee), so the maker is not asked to receive it twice. **The v1.0.2 change** makes
fee collection best-effort: if `_tryPullFee` fails, `amountNetPulled` is **not** incremented,
so the identity below stays exact.

### tokenOut (maker pays), Aqua mode, SwapVM.sol:266

```
AQUA.pull(maker, orderHash, tokenOut, amountOut, to)   // real: maker→to; virtual: −amountOut
```

(with optional WETH unwrap: pull to router, then `IWETH.safeWithdrawTo(amountOut, to)`).

### Fee legs (Fee.sol)

- flat fee: charged in tokenIn, retained by maker (no external transfer) — affects rate only.
- protocol / aqua-protocol fee: pulled to `feeTo`. `_tryPullFee` (v1.0.2) try/catch; on success
  increments `amountNetPulled` by the fee; on failure emits `ProtocolFeeSkipped`, no increment.

---

## 2. Conservation identities (must hold to the wei)

For a swap tokenIn→tokenOut with protocol fee `f` in tokenIn to `feeTo`:

```
(I)  taker.tokenIn  Δ = −amountIn
(II) taker.tokenOut Δ = +amountOut
(III) maker.tokenIn  Δ = +(amountIn − f)          [virtual and real equal]
(IV) maker.tokenOut  Δ = −amountOut               [virtual and real equal]
(V)  feeTo.tokenIn   Δ = +f
(VI) Σ tokenIn  over {taker,maker,feeTo} = 0  ⇔  −amountIn + (amountIn−f) + f = 0   ✓
(VII) Σ tokenOut over {taker,maker}      = 0  ⇔  +amountOut − amountOut = 0          ✓
```

When the fee is **skipped** (v1.0.2 best-effort): `f = 0`, identities collapse to the no-fee
case; the *protocol* forgoes revenue but no counterparty loses value.

---

## 3. Empirical verification (the ledger, checked)

`AdvCanonicalFull._doSwap` asserts, per swap, on the real deployed program
`[aquaProtocolFee][concentrate][xycSwap]`:

| Identity | Assertion in PoC |
|----------|------------------|
| (I)  | `a.tkIn − b.tkIn == amountIn` |
| (II) | `b.tkOut − a.tkOut == amountOut` |
| (III) real==virtual | `makerRealInΔ == makerVirtualInΔ` AND `makerVirtualInΔ == amountIn − feeΔ` |
| (IV) real==virtual  | `makerRealOutΔ == makerVirtualOutΔ` AND `makerVirtualOutΔ == amountOut` |
| (V)  | `feeΔ ≤ amountIn` (fee is a fraction of in) |
| (VI) | `−amountIn + makerRealInΔ + feeΔ == 0` |
| (VII)| `amountOut + makerRealOutΔ == 0` |

Result: **all identities hold across 3000 fuzz runs** over every taker lever
(direction, exactIn/exactOut, isFirstTransferFromTaker, useTransferFromAndAquaPush) and fee
bps 0..50%. AdvFeeDecay verifies the same identities with Decay in the program and a second
time-warped swap. AdvSkipConc verifies them in the fee-skip regime.

---

## 4. Branch-coverage checklist

| Settlement branch | Covered by |
|-------------------|-----------|
| tokenIn push path (A) | AdvCanonicalFull (useTransferFromAndAquaPush=true fuzzed), AdvConservation.tfap |
| tokenIn check path (B) + preTransferIn push | AdvCanonicalFull (false), AdvConservation.callback |
| tokenOut Aqua pull | every PoC |
| tokenOut WETH unwrap | analyzed (K4-10): non-WETH reverts (self-grief); WETH unwraps to `to` |
| fee pulled to feeTo | AdvCanonicalFull, AdvFeeDecay, AdvFeeStack |
| fee skipped (best-effort) | AdvSkipConc, AdvCanonicalFull (skip regime) |
| amountNetPulled > 0 | fee legs in AdvCanonicalFull/FeeDecay |

Every branch conserves. No branch lets the taker underpay, the maker overpay beyond the curve,
or the fee accounting drift.
