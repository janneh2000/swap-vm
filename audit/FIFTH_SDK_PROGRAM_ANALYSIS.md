# FIFTH_SDK_PROGRAM_ANALYSIS

Phase 3 — the builder/encoder ⟷ VM/decoder boundary. The on-chain builders live in the libs
(`MakerTraitsLib.build`, `TakerTraitsLib.build`, each instruction's `*ArgsBuilder`); the
off-chain TS SDK is a separate package (out of the eligible-release scope) but must produce the
identical byte layout, so the layout contract below is what any SDK must honor and what an
attacker would try to desynchronize.

## Program byte layout

Program = concatenation of instructions `[opcode:1][argsLen:1][args:argsLen]…`, executed by
`ContextLib.runLoop` (VM.sol). `args = programBytes[pc:pc+argsLen]` uses the **Solidity builtin
calldata slice**, which reverts if `pc+argsLen > programBytes.length` or `pc > pc+argsLen`
(bounds-checked). `argsLen` is a single byte (≤255).

## Order.data layout (MakerTraitsLib.build)

`data = [preInHook?][preInData][postInHook?][postInData][preOutHook?][preOutData][postOutHook?][postOutData][program]`.
The four 16-bit boundary offsets `index0..index3` are packed into `traits` (bits 160–223); the
program is `data[index3 : data.length]`. **All of traits and data are in the order and hashed.**

## takerTraitsAndData layout (TakerTraitsLib.build/parse)

`[header:22][threshold][to][deadline][preInHook][postInHook][preOutHook][postOutHook][preInCb][preOutCb][instructionsArgs][signature]`
Header = 20-byte `slicesIndexes` (ten 16-bit offsets index0..index9) + 2-byte flags. **None of
takerData is hashed** — it is the taker's own choice each call.

## Where an attacker attacks the boundary, and why it holds

| Desync attempt | Analysis | Verdict |
|----------------|----------|---------|
| Change program bytes, keep orderHash | orderHash re-encodes the decoded order (Aqua) / hashes keccak256(data) (sig); program is a slice of that same data → any change changes the hash → empty balances / bad signature → revert | closed (ORDER_BINDING_MAP; AdvAuth) |
| Non-canonical ABI encoding of `order` s.t. hash matches but program slice differs | hash and program both read the *same decoded* `order.data` calldata region; `abi.encode(order)` re-serializes the decoded value → no divergence | closed (SEMANTIC_DIFFERENTIALS) |
| Malformed taker slice offsets (non-monotonic → `Calldata.slice` begin>end underflow) | offsets are taker-controlled and un-hashed, but every taker slice is either length-gated to a safe default (threshold/to/deadline) or self-scoped (callback data / instructionsArgs / hookData) → self-DoS or waived own-protection; the maker's accounting is unreachable | closed (AdvIntegrationDecode; KILL K5-01) |
| Build program against the WRONG opcode table (base vs Aqua) | same bytes, different logic — but an order can only execute on the router it was shipped/signed for (ROUTER_CORE_DIFF §1) → wrong-router execution reverts | closed as attack; maker/SDK footgun (KILL K5-07) |
| Malformed instruction args (wrong argsLen, truncated) | builtin calldata slice bounds-checks; each ArgsBuilder `parse*` uses guarded `Calldata.slice(…, selector)` that reverts on short args (OZ M-3 fix) | closed |

## SDK correctness hazards (not vulnerabilities, but hardening notes)

- **Opcode-table coupling:** the SDK must select the opcode table matching the target router.
  A mismatch silently misexecutes (see ROUTER_CORE_DIFF). Recommend a program version/table tag.
- **Offset monotonicity:** the on-chain builders always emit monotonic offsets; a hand-rolled or
  buggy encoder could emit `begin>end`. On the maker side this is hash-bound self-harm; on the
  taker side it only waives the taker's own protections. A `begin<=end` assert in `Calldata.slice`
  would convert these to clean reverts (defense-in-depth; the current code only checks
  `end<=length`).
