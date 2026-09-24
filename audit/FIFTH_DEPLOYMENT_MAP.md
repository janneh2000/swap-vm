# FIFTH_DEPLOYMENT_MAP

Phase 1 — the real production topology, reconstructed from source + `script/` + `broadcast/`.
Eligible release: SwapVM v1.0.2 (`32c687c`), Aqua v1.0.0 (`81c26e4`).

## The call path

```
USER/TAKER ──swap(order, tokenIn, tokenOut, amount, takerTraitsAndData)──▶ AquaSwapVMRouter
   AquaSwapVMRouter = Simulator + SwapVM + AquaOpcodes            (src/routers/AquaSwapVMRouter.sol)
      │  hash(order) ─ Aqua mode: keccak256(abi.encode(order))    (SwapVM.sol:97)
      │  balances    ─ AQUA.safeBalances(maker, address(this), orderHash, tIn, tOut)  (:194)
      │  runLoop     ─ interprets order program via _instructions()==_opcodes()  (AquaOpcodes)
      │                 ├─ curves (XYCSwap/XYCConcentrate/PeggedSwap/Decay)
      │                 ├─ Fee (flat/protocol/aqua-protocol/dynamic/aqua-dynamic)
      │                 │     dynamic ⟶ staticcall(feeProvider)   ← the only external call in-loop
      │                 └─ Extruction ⟶ call(maker-chosen target)  ← maker escape hatch
      │  settlement  ─ _transferIn / _transferOut ⟶ AQUA.pull / AQUA.push
      ▼
   AQUA (Aqua.sol) — non-custodial virtual-balance ledger, _balances[maker][app][hash][token]
      pull: from = _balances[maker][msg.sender=app][hash][token]  (real maker→to)
      push: credits _balances[maker][app][hash][token]            (real msg.sender→maker)
```

## Deployed contracts & configuration

| Component | What is deployed | Config source |
|-----------|------------------|---------------|
| Router (production) | **AquaSwapVMRouter** = `Simulator + SwapVM + AquaOpcodes` | `DeployAquaSwapVMRouter.s.sol` |
| Router ctor args | `(aqua, weth, owner, name, version)` | `Config.readSwapVMRouterParameters()` / env |
| Alt routers (NOT the Aqua production path) | SwapVMRouter (base Opcodes, sig mode), LimitSwapVMRouter, *Debug variants | separate deploy scripts |
| Ledger | **Aqua** (immutable, non-upgradeable) | `OPS_AQUA_ADDRESS` |
| Deployment method | CREATE / **CREATE3 pads** (`__DeployPadCreate[3].s.sol`) → deterministic addresses across chains 1,10,56,100,130,137,146,324,4663,8453,42161,43114,59144 | `broadcast/` |
| Global fee provider | **NONE** — there is no protocol-wide fee-provider address in any constructor; dynamic-fee providers are supplied *per program* by the maker | `Fee.sol` ctor takes only `aqua` |
| Owner privileges | `Rescuable(owner)` — owner can rescue stuck funds only (no swap-path power) | ctor |

## Facts that matter downstream

1. **Router is the `app` key.** `AQUA.safeBalances(maker, address(this), …)` and `AQUA.pull(...)` are keyed by the executing router (`address(this)` / `msg.sender`). An order's liquidity lives under exactly the router the maker shipped to. (Feeds ORDER_BINDING_MAP, ROUTER_CORE_DIFF.)
2. **No global fee provider.** Dynamic fee providers are per-program, maker-chosen, hash-bound. (Feeds FEE_PROVIDER_ANALYSIS.)
3. **Debug/Limit routers are separate deployments** with separate addresses; they are not the Aqua production path and cannot borrow its balances.
4. **CREATE3 ⇒ same router address on every chain.** Sig-mode orders are still chain-separated by the EIP-712 domain (chainId). Aqua-mode orders are chain-separated by on-chain ship (balances are per-chain Aqua deployment). (Feeds ORDER_BINDING_MAP §cross-chain.)
5. **Immutability.** SwapVM `AQUA` is immutable; Aqua `_balances` is the only mutable economic state; routers are non-upgradeable. There is no attacker-settable configuration on the swap path. (Feeds SHARED_STATE_MAP.)
