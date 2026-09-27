# FOURTH_CAMPAIGN_AUTHORIZATION_MAP

What binds "the program that runs" and "the funds it can move" to "what the maker authorized"
(RC-5). Two authorization modes; both bind the **entire order, including the program bytes**.

Code refs: `SwapVM.sol:97-107` (hash), `:147-198` (mode gate), `:162-214` (swap),
`Aqua.sol:40-51` (ship → strategyHash).

---

## 1. The hash

```solidity
function hash(order) {
  if (useAquaInsteadOfSignature) return keccak256(abi.encode(order));      // Aqua mode
  else return _hashTypedDataV4(keccak256(abi.encode( ... order fields ... ))); // sig mode (EIP-712)
}
```

In both modes the hash is over `abi.encode(order)`, and `order.data` contains the program
bytes (`order.traits.program(order.data)`). **Any change to the program changes the hash.**

## 2. Aqua mode binding

- Maker ships: `Aqua.ship(app=router, strategy=abi.encode(order), tokens, amounts)` →
  `strategyHash = keccak256(strategy) = keccak256(abi.encode(order))`.
- Swap: `orderHash = keccak256(abi.encode(order))`; balances fetched via
  `AQUA.safeBalances(maker, router, orderHash, tokenIn, tokenOut)`.
- **Therefore `orderHash ≡ strategyHash`.** If a taker submits an order whose program (or any
  field) differs from what the maker shipped, `orderHash` differs, `safeBalances` reads a
  *different, empty* cell → `balanceIn/Out = 0` → the curve cannot produce a fundable swap and
  settlement reverts (pull underflow / sufficiency fail). The taker cannot run an unauthorized
  program against the maker's funds.

## 3. Signature mode binding

- `require(order.maker.recoverOrIsValidSignature(orderHash, signature))`. `orderHash` covers
  `abi.encode(order)` incl. the program → a tampered program fails signature recovery. (OZ M-6
  "signing loose non-Aqua strategy": the signed digest binds the full order; there is no
  program field left unsigned.)

## 4. Reentrancy / replay

- `_reentrancyGuards[orderHash].lock()/.unlock()` (transient) per orderHash → no re-entrant swap
  on the same order within a call.
- Aqua-mode balances are consumed from the shipped cell; there is no signature nonce because the
  cell balance itself is the budget. Replaying the same order just does another swap against the
  remaining balance — the maker's own liquidity, priced by the same curve. Not a replay bug.

## 5. Empirical checks (AdvAuth)

| Attack | Result |
|--------|--------|
| Tamper one byte of the program, keep shipped balances | REVERTS (orderHash≠strategyHash → empty balances) |
| Swap a token the strategy didn't ship (foreign token) | REVERTS (empty cell for that token) |
| tokenIn == tokenOut (degenerate self-swap) | REVERTS |
| Submit order with different maker | REVERTS (cell keyed by maker) |

## 6. What a taker CAN control (and why it's safe)

The taker controls `TakerTraits + takerData`: direction, exactIn/exactOut, thresholds,
`isFirstTransferFromTaker`, `useTransferFromAndAquaPush`, `to`, callbacks, `instructionsArgs`,
and (sig mode) the signature. None of these change the **program** or the **maker's authorized
curve**; they only choose how the taker settles their own side. Every combination was fuzzed in
AdvCanonicalFull/AdvConservation and conserves (SETTLEMENT_LEDGER).

`instructionsArgs` lets the maker's program read taker-supplied args at specified opcodes — but
only where the maker's program explicitly consumes them, and always within the maker-authored
instruction logic. This does not let the taker inject new instructions.

**Conclusion:** authorization binds the full program to the funds in both modes. There is no
authorization-context drift (RC-5) reachable by a taker or third party.
