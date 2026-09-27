# SCOPE

## Program
- Target: **1inch Aqua** — HackenProof (`https://hackenproof.com/programs/1inch-aqua`)
- NOTE: hackenproof.com is **blocked by this environment's egress proxy** — the live brief could
  not be fetched. Scope below is taken from the task brief + repo docs. Any candidate must be
  re-checked against the live brief before treating a severity/OOS call as final.

## Eligible releases (authoritative code analyzed)
| Repo | Tag | Commit (`^{}`) | Local clone |
|------|-----|----------------|-------------|
| SwapVM (primary) | v1.0.2 | `32c687c2b73101fc26549e48fa1ff8a4d73afbac` | `/home/user/scope-swap-vm` |
| Aqua (secondary) | v1.0.0 | `81c26e4619ce21556ab02b3284ee2685de21fb18` | `/home/user/scope-aqua` |

### Important scope correction
- The working forks `janneh2000/swap-vm` and `janneh2000/aqua` are **post-release snapshots**:
  - `janneh2000/swap-vm@main` (feb1641) is *significantly* refactored vs v1.0.2 (Hardhat-first,
    `contracts/` layout, extra instructions incl. permit2 / relative-time / OrderRegistrator /
    Strategies / Whitelist / PiecewiseLinearScale). **Out of scope** except where identical to v1.0.2.
  - `janneh2000/aqua@ef24220` core is **functionally identical** to v1.0.0 (only formatting differs) —
    verified by diff. So Aqua reasoning transfers directly.
- All analysis is performed against the cloned eligible tags (`scope-swap-vm`, `scope-aqua`).

## Deployed contracts (per Aqua README; deterministic same-address multichain)
- Aqua registry: `0x1111113ccf1426a8e30e2bff5e005d929bf6a90a`
- SwapVM router:  `0x111111338c5091e8440b67b168bae16a668ac0de`
- v1.0.x router ABI: `swap(order, tokenIn, tokenOut, amount, takerData)` — taker passes tokenIn/tokenOut explicitly.
- Router *type* actually deployed at that address is not determinable from the local repo config
  (deploy scripts exist for SwapVMRouter / AquaSwapVMRouter / LimitSwapVMRouter). Both the full
  `Opcodes` router and `AquaOpcodes` router share the base `SwapVM` Aqua settlement logic, so
  composition seams in the base are in scope regardless.

## In scope (code)
- `scope-swap-vm/src/**` (SwapVM core, libs, opcodes, routers, instructions)
- `scope-aqua/src/**` (Aqua registry, AquaApp, AquaRouter, Balance lib)

## Program rules (from task brief)
- Local Foundry/Anvil + controlled fixtures only. **Do not modify production contracts.**
- Do not access other users' data. **Do not submit. Do not fabricate. No theoretical-only findings.**
- A real finding = demonstrated security/economic impact with a runnable A/B PoC.

## Known duplicate pressure (DO-NOT-primary-target)
- v1.0.2 **Fee update** was differentially audited (Bailsec, Decurity, MixBytes, OpenZeppelin, Theori).
  `Fee.sol` `amountNetPulled` machinery explicitly cites *OpenZeppelin M-09* and *Theori #10*.
- Also known/likely-audited: XYC rounding, Decay, TWAP, hook-flag, BaseFeeAdjuster.
- Original OZ audit "1inch Aqua and SwapVM MVP v1.0".
