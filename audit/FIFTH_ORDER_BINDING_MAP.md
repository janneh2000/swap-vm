# FIFTH_ORDER_BINDING_MAP

Phase 4 — the field-by-field data-dependency graph: SIGNED/HASHED? VALIDATED? USED/SETTLED?
The target primitive is "authorized semantics ≠ executed semantics." None found.

## The order (maker side)

`Order { address maker; uint256 traits; bytes data }`.
- Aqua mode: `orderHash = keccak256(abi.encode(order))` (SwapVM.sol:99). Covers maker+traits+data.
- Sig mode: `orderHash = _hashTypedDataV4(keccak256(abi.encode(ORDER_TYPEHASH, maker, traits, keccak256(data))))`.
  Covers maker+traits+data, **plus chainId + verifyingContract** via the EIP-712 domain.

| Field (inside order) | Hashed | Validated | Used in execution | Divergence? |
|----------------------|:------:|:---------:|--------------------|-------------|
| maker | ✓ | balances keyed by it / sig recovered to it | pull/push counterparty | none |
| traits: flags (unwrap/useAqua/allowZeroIn/hooks) | ✓ | `MakerTraits.validate` (tokenIn≠tokenOut, amountIn>0∨allowZero) | gate settlement paths | none |
| traits: receiver (bits 0–159) | ✓ | Aqua mode requires receiver==maker (:232) | maker payout target | none |
| traits: data offsets index0–3 (bits 160–223) | ✓ | slice bounds (`end≤len`) | carve program/hooks out of data | maker-scoped only |
| data: hook targets + hook data | ✓ | — | maker hooks | maker-scoped |
| data: program bytes | ✓ | runLoop bounds | executed | **bound** (slice of hashed data) |

**Program ⇔ hash binding is tight**: the program is `data[index3:len]`, index3∈traits, data∈order,
all hashed; and `abi.encode(order)` re-serializes the *decoded* data, so what is hashed is exactly
what is sliced. Empirically: AdvAuth (tamper program → revert), AdvIntegrationRouter (hash
router-independent, yet only correct-router balances exist).

## The call arguments (taker side — NOT hashed)

`swap(order, tokenIn, tokenOut, amount, takerTraitsAndData)`.

| Field | Hashed | Validated | Used | Divergence risk & resolution |
|-------|:------:|-----------|------|------------------------------|
| tokenIn / tokenOut | ✗ | must match a shipped token (else empty balance) & tokenIn≠tokenOut | curve + settlement | AUTHORIZED TOKEN == SETTLED TOKEN: the token pair selects the Aqua balance cell; a pair the maker never shipped ⇒ empty ⇒ revert. No "authorized token ≠ settled token." |
| amount | ✗ | `TakerTraits.validate`: exactIn⇒`amount==amountIn`; exactOut⇒`amount==amountOut` | seeds the register | AUTHORIZED LIMIT == ACTUAL: binds the taker's declared amount to the computed one (proven to reject Extruction-forced mismatch, AdvIntegrationExtruction) |
| takerTraits flags/offsets/threshold/to/deadline | ✗ | self-consistency; threshold/deadline enforced for the taker | taker protections + payout dest | taker-only: waiving them is self-harm (AdvIntegrationDecode) |
| instructionsArgs | ✗ | consumed only by Extruction (maker opt-in) | fed to maker's Extruction target | maker opts in; taker already controls the content |
| signature | ✗ | sig mode: must recover to maker over orderHash | authorize order | can't forge; binds order incl. program+chain+router |

## Cross-chain / cross-router replay

- **Sig mode:** domain has chainId + verifyingContract ⇒ no cross-chain, no cross-router replay.
- **Aqua mode:** orderHash is chain/router-independent, BUT authorization = existence of an
  on-chain balance under (maker, thisRouter, hash). Balances are per-chain (separate Aqua) and
  per-router (app key). To have funds swappable on chain X / router R, the maker must `ship` on
  X under R. So chain/router-independence of the hash grants no replay of funds.

## Conclusion

Every field is either (a) hashed and bound, or (b) taker-chosen and self-scoped, or (c) a
token/amount selector that is validated against the maker's shipped liquidity. No field is
"authorized as X but executed as Y" to a counterparty's benefit.
