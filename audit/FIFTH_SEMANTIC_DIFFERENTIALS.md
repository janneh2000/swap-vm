# FIFTH_SEMANTIC_DIFFERENTIALS

Phases 11 & 13 — "one representation, two security-relevant interpretations." Each row is a place
where two components could disagree about the meaning of the same bytes; the resolution shows why
the disagreement is either impossible or attacker-harmless.

| # | Representation | Interpretation A | Interpretation B | Reachable divergence for attacker gain? |
|---|----------------|------------------|------------------|------------------------------------------|
| SD-1 | `order` calldata | `hash()` = keccak256(abi.encode(order)) (re-encoded canonical) | program = calldata slice of decoded `order.data` | **No** — both read the same decoded `order.data`; re-encode uses the decoded value. Non-canonical ABI can't split them. (ORDER_BINDING, SDK_PROGRAM) |
| SD-2 | program bytes | AquaOpcodes table (deployed router) | base Opcodes table (SwapVMRouter) | **No** — same bytes differ per router, but an order executes only on the router it was shipped/signed for (app-keyed balances / EIP-712 domain). Proven: AdvIntegrationRouter. |
| SD-3 | taker slice offsets | canonical builder (monotonic) | hand-crafted (non-monotonic → Calldata underflow) | **No** — taker slices are self-scoped / length-gated; malformed → self-DoS or waived own-protection; maker unreachable. Proven: AdvIntegrationDecode. |
| SD-4 | taker `amount` + isExactIn | taker's declared trade size | curve/Extruction-computed amountIn/Out | **No** — `TakerTraits.validate` binds `amount==amountIn` (exactIn) / `amount==amountOut` (exactOut). Extruction forcing a different value reverts. Proven: AdvIntegrationExtruction. |
| SD-5 | tokenIn/tokenOut args | taker's chosen pair | the shipped strategy's token cell | **No** — a pair the maker didn't ship ⇒ empty balance ⇒ revert. "Authorized token == settled token." (AdvAuth) |
| SD-6 | quote() vs swap() | static: fee computed, not moved; IStaticExtruction | swap: fee moved; IExtruction | Amounts identical; only fee-movement / interface differ. Documented; no fund divergence; taker keeps threshold. (ROUTER_CORE_DIFF §2) |
| SD-7 | fee bps source (dynamic) | provider staticcall return | in-scope fee math | provider maker-chosen, staticcall-isolated, feeBps≤100%, to≠0; maker pays. (FEE_PROVIDER_ANALYSIS) |
| SD-8 | token transfer amount | Aqua virtual delta | ERC20 real delta | Equal for standard tokens; FoT/rebasing diverge but only on maker-chosen inventory; CEI keeps Aqua consistent; taker can't force it on a standard-token maker. (TOKEN_SEMANTICS) |
| SD-9 | strategy bytes at ship vs order at swap | Aqua: strategyHash=keccak256(strategy) | SwapVM: orderHash=keccak256(abi.encode(order)) | Must be byte-identical (`strategy==abi.encode(order)`) for balances to resolve; abi.encode injective ⇒ no two distinct orders share a shipped cell. (ORDER_BINDING §replay) |

## Method note

The differentials were probed both by static reasoning (data-dependency graph in
ORDER_BINDING_MAP) and by the semantic-differential PoCs in INTEGRATION_FUZZ_RESULTS, which build
representations *two ways* (canonical builder vs hand-crafted / malicious target) and assert the
maker-side settlement is identical or reverts. No differential produced an attacker-favorable
divergence.
