# THREAT MODEL — SwapVM × Aqua composition

## Actors
- **Maker (LP):** signs an EIP-712 order OR ships a strategy to Aqua. Controls the **program bytecode**,
  maker traits, hooks, token pair (encoded in program instructions), fee params. Trusted to write a sane
  program (program bugs = maker's own risk). Approves router (sig mode) or Aqua (Aqua mode) for tokenOut.
- **Taker (attacker candidate):** calls `swap(order, tokenIn, tokenOut, amount, takerData)`. Controls:
  `tokenIn`, `tokenOut` (only constrained by `tokenIn != tokenOut` + program + Aqua `safeBalances`),
  `amount`, `isExactIn`, direction, `to` recipient, partial-fill, transfer ordering
  (`isFirstTransferFromTaker`), Aqua pay-mode (`useTransferFromAndAquaPush`), taker `shouldUnwrapWeth`,
  hooks/callbacks bodies, and `instructionsArgs` (consumed only by Extruction in v1.0.2).
- **Third parties:** anyone can `push` to an active strategy (donation); anyone can `ship`/`dock` their OWN
  strategies; fee providers (maker-chosen) return feeBps/recipient via staticcall.
- **Owner:** `rescueFunds` only.

## Assets
- Maker's real ERC20 balances (held in wallet, moved via Aqua `pull`/`push` or router `transferFrom`).
- Aqua **virtual balances** `balances[maker][app][strategyHash][token]` (uint248 amount + uint8 tokensCount).
- Router-custodied funds are transient (settlement flows through; no pooled value normally).

## Trust / authorization models (the drift surface)
1. **Signature mode:** `orderHash = EIP-712(_hashTypedDataV4(Order(maker,traits,keccak256(data))))`.
   Bound to router via EIP-712 domain (name/version + verifyingContract=router). Verified every fill.
2. **Aqua mode (`useAquaInsteadOfSignature`):** `orderHash = keccak256(abi.encode(order))`. NO signature.
   `orderHash` **doubles as the Aqua `strategyHash`**; app = router (`address(this)`). Authorization is
   "maker has active Aqua balances for (router, orderHash, tokens)". Bound to router via Aqua `app` field.
   Custom receiver + maker WETH-unwrap forbidden in this mode.

## The composition pipeline (mission's central model) and where meaning can drift
```
off-chain Order {maker,traits,data}
 → MakerTraits packs flags/receiver/data-slice offsets; data = [hookslices..][program]
 → orderHash  (EIP-712 digest  |  keccak256(abi.encode(order)))          [BINDING]
 → auth       (ECDSA/1271       |  Aqua safeBalances active-strategy)     [AUTH]
 → program bytes = data.slice(index3, len)
 → runLoop: [op][len][args]* → ctx.vm.opcodes[op](ctx,args)              [DISPATCH]
 → SwapRegisters {balanceIn,balanceOut,amountIn,amountOut,amountNetPulled} [STATE]
 → order.traits.validate(tokenIn,tokenOut,amountIn) + takerTraits.validate  [POST-CHECK]
 → hooks/callbacks (maker hooks + taker callbacks, reentrancy guard held)   [EXTERNAL]
 → settlement: transferOut/transferIn (order chosen by taker) via Aqua pull/push or transferFrom
```

## Drift categories being hunted
- **SEMANTIC/SERIALIZATION:** order.data slice offsets in traits; abi.encode(order) canonicalization vs
  Aqua `keccak256(strategy)`; program tail parsing; taker `tokenIn/tokenOut` unbound by core.
- **AUTHORIZATION-CONTEXT:** signature vs Aqua orderHash domains; router binding (domain vs Aqua app);
  same strategy shipped to multiple routers → different opcode meaning.
- **STATE-REPRESENTATION:** uint248 amount + uint8 tokensCount packing; register vs real Aqua balance;
  Decay/Balances overriding Aqua-loaded balances.
- **EXECUTION-CONTEXT:** opcode-table drift across routers; jump into mid-instruction; nested runLoop
  (fees wrap the program); Extruction rewriting all registers + nextPC.
- **ACCOUNTING-CONTEXT:** `amountNetPulled` gating the Aqua tokenIn sufficiency check; fee pull vs push;
  shared liquidity across strategies (virtual > real).
- **TEMPORAL/SETTLEMENT:** transferOut-first vs transferIn-first; taker callback between the two;
  absolute snapshot check `balanceIn >= originalAquaBalanceIn + amountIn - amountNetPulled`.

## What is explicitly de-prioritized (known / audited)
Fee.sol amountNetPulled first-order behavior; XYC/Concentrate rounding; Decay/TWAP/BaseFeeAdjuster
first-order; obvious reentrancy; simple over/underflow; generic IDOR/missing-require. We hunt the
SECOND-ORDER composition seam, not these.
