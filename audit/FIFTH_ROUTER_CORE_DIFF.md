# FIFTH_ROUTER_CORE_DIFF

Phase 2 & 12 — "router thinks A, core thinks B." The router is a thin composition
(`Simulator + SwapVM + <opcode table>`); it adds **no validation layer** that could diverge
from the core. The one real divergence between the two routers is the **opcode table**, and the
one documented divergence inside a router is **quote vs swap**. Both are analyzed for
attacker benefit; neither yields one.

---

## 1. Opcode-table divergence between routers (the headline of this phase)

`AquaSwapVMRouter` uses `AquaOpcodes._opcodes()`; `SwapVMRouter` uses `Opcodes._opcodes()`.
They assign **different instructions to the same opcode number**:

| opcode | base `Opcodes` (SwapVMRouter) | `AquaOpcodes` (AquaSwapVMRouter, DEPLOYED) |
|:---:|---|---|
| 11–17 | Controls (jump/…/supplyShareGte) | Controls (identical) |
| 18 | Balances._staticBalancesXD | **XYCSwap._xycSwapXD** |
| 19 | Balances._dynamicBalancesXD | **XYCConcentrate** |
| 20 | Invalidators._invalidateBit1D | **Decay** |
| 21 | Invalidators._invalidateTokenIn1D | **Controls._salt** |
| 22 | Invalidators._invalidateTokenOut1D | **Fee._flatFeeAmountInXD** |
| 23 | XYCSwap._xycSwapXD | _notInstruction |
| 24 | XYCConcentrate | _notInstruction |
| 25 | Decay | _notInstruction |
| 28 | MinRate._requireMinRate1D | **Fee._protocolFeeAmountInXD** |
| 29 | MinRate._adjustMinRate1D | **Fee._aquaProtocolFeeAmountInXD** |
| 30 | DutchAuction…In | **Fee._dynamicProtocolFeeAmountInXD** |
| 31 | DutchAuction…Out | **Fee._aquaDynamicProtocolFeeAmountInXD** |
| 32 | BaseFeeAdjuster | **PeggedSwap** |
| 33 | TWAPSwap._twap | **Extruction._extruction** |
| 34 | Extruction._extruction | Controls._onlyTxOriginTokenBalanceNonZero |
| 35–46 | salt, Fee/FeeExperimental, PeggedSwap, Fee(protocol/aqua/dynamic) | (table length 34; no such indices) |

⇒ **The same program bytes execute different logic on the two routers.** If this divergence
could be triggered — get an order authorized for router A to run on router B — a program the
maker built as (say) "PeggedSwap" (opcode 32 on Aqua) would run as "BaseFeeAdjuster" (opcode 32
on base). That would be a classic integration break.

**Why it cannot be triggered (the binding closes it):**
- **Aqua mode:** balances are keyed by the executing router (`AQUA.safeBalances(maker,
  address(this), hash, …)`, `AQUA.pull(maker, /*app=*/msg.sender, …)`). An order whose liquidity
  was shipped under router A yields **empty balances** on router B → zero reserves → `amountOut==0`
  (rejected by `TakerTraits.validate`) or pull underflow → **revert**. Proven:
  `AdvIntegrationRouter.test_cross_router_execution_fails_safe` (ships on router1, executes on a
  second AquaSwapVMRouter → reverts, router1 balances intact; and confirms the Aqua orderHash is
  router-independent, so it is *only* the balance keying that binds).
- **Signature mode:** `hash()` uses `_hashTypedDataV4(...)`, whose domain includes
  `verifyingContract` (the router) and `chainId`. A signature valid for router A fails
  `recoverOrIsValidSignature` on router B.

**Verdict:** real divergence, but **not reachable** by an unprivileged actor. It is a
maker/SDK *configuration hazard* (build the program against the wrong table → your own strategy
misbehaves), documented in SDK_PROGRAM_ANALYSIS and CANDIDATES C5-07 (KILLED). Hardening note:
a version/table byte in the program or a per-router opcode namespace would turn a silent
misexecution into a clean revert.

## 2. quote() vs swap() divergence (documented in-code)

`quote` runs the same program with `isStaticContext = true`. Fee instructions compute the fee
but **skip the transfer/pull** (`if (!ctx.vm.isStaticContext)`), and Extruction calls
`IStaticExtruction` instead of `IExtruction`. Consequences:
- **Amounts are identical** between quote and swap (the divergence is only *whether the fee token
  actually moves* and *which Extruction interface* is used). The NatSpec states this explicitly.
- `quote` takes **no reentrancy lock** and performs **no settlement** — it is side-effect-free
  (all state-changing branches are gated by `!isStaticContext`; curves are pure).
- A taker who trusts a quote could see a swap revert (maker can't cover fee / non-deterministic
  Extruction target), but **no funds move on quote** and the taker keeps slippage protection
  (threshold) on the real swap.

**Verdict:** a UX/consistency caveat the code itself flags for makers of Extruction/fee
strategies; not a fund-loss path. CANDIDATES C5-05 (KILLED).

## 3. Router adds no divergent validation

Neither router overrides `swap`, `_transferIn/out`, `hash`, or `validate`. The only override is
`_instructions()` (the opcode table). There is no "router validates X but core reinterprets it"
surface beyond §1. `Simulator` adds an off-chain `simulate` entrypoint that **always reverts**
with the result (revert-based simulation) — it cannot settle or mutate state.
