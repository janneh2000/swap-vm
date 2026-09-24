# FIFTH_FEE_PROVIDER_ANALYSIS

Phase 5 — everything outside Fee.sol's own math that supplies or influences a fee. The dynamic
variants (`_dynamicProtocolFeeAmountInXD`, `_aquaDynamicProtocolFeeAmountInXD`, both DEPLOYED in
AquaOpcodes at 30/31) call an external `IProtocolFeeProvider`.

## Who controls the provider, and how it is called

- **Provider address = a program arg** (`FeeArgsBuilder.parseDynamicProtocolFee` reads 20 bytes
  from the instruction args). The program is hash-bound ⇒ **the provider is maker-chosen, fixed
  per strategy, and cannot be substituted by a taker or third party.**
- **The call is a `staticcall`** (`feeProvider.staticcall(abi.encodeCall(IProtocolFeeProvider.
  getFeeBpsAndRecipient, (orderHash, maker, taker, tokenIn, tokenOut, isExactIn)))`). The provider
  **cannot mutate state** — no reentrancy that writes, no cross-order state poisoning from inside
  the call.
- **Return is validated:** `require(success && result.length == 64)`, `(feeBps, to)=abi.decode`,
  `require(feeBps <= BPS)` (≤100%), and if `feeBps!=0` then `require(to != address(0))`.
- **State changes happen after the call** (fee computed on the post-call `feeBps`); the code
  comment states the provider "MUST NOT rely on intermediate swap state."
- **Funds come from the MAKER:** the fee is `safeTransferFrom(maker, to)` (or `AQUA.pull(maker,…)`
  for the aqua variant). The recipient `to` is provider-chosen — but the payer is always the
  maker who chose the provider.

## Attack matrix

| Attempt | Actor | Result |
|---------|-------|--------|
| Substitute a malicious provider | taker/3P | impossible — provider addr is hash-bound |
| Malicious provider returns feeBps=100%, to=attacker | maker's provider | pulls from the MAKER to attacker; maker chose the provider ⇒ maker self-harm; taker unaffected beyond reduced amountIn (their exactIn amount still binds, threshold protects) |
| Provider reenters to poison another order | provider | staticcall ⇒ cannot write state; cannot reenter a state-changing path |
| Provider returns huge revert data / gas bomb | provider | `success && length==64` check; the code comment flags gas griefing as a taker-caution; taker chooses whether to touch an Extruction/dynamic-fee strategy |
| Provider reads taker-manipulable shared state to set feeBps per-taker | provider | any such logic is in the OUT-OF-SCOPE provider contract; in-scope code enforces feeBps≤100%, to≠0, staticcall isolation, maker-pays. A provider that mis-prices harms the maker who deployed it |
| feeBps==BPS on exactOut ⇒ `/(BPS-feeBps)` division by zero | maker/provider | reverts the maker's own exactOut; maker/provider-scoped |

## Global fee provider?

**None.** No constructor or router state holds a protocol-wide fee provider (DEPLOYMENT_MAP).
There is therefore no shared provider whose state one order could poison for another. Each
dynamic-fee strategy names its own provider in its own hash-bound program.

## Verdict

The dynamic fee provider is a **maker-scoped trust boundary**, fully isolated by staticcall and
bounded by the in-scope validations. No unprivileged taker/third-party path changes a victim's
fee or extracts value. Any exploit would live in a maker's own out-of-scope provider contract and
would harm only that maker. CANDIDATES C5-03 (KILLED).
