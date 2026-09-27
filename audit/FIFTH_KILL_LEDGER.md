# FIFTH_KILL_LEDGER

Why each fifth-campaign integration candidate does not work. A kill is valid only with a runnable
PoC (green = attack produced no impact) or a read-confirmed structural guarantee with the exact
code location. Toolchain: forge (solc 0.8.30, via_ir, opt 700), deployed AquaSwapVMRouter →
AquaOpcodes, real Aqua. Full suite: **18 files, 41 tests, 0 failed.**

| ID | Candidate | Kill evidence | Type |
|----|-----------|---------------|------|
| K5-01 | Calldata.slice begin>end underflow via taker offsets | AdvIntegrationDecode (3 tests, 256-run offset+tail fuzz): malformed offsets revert (huge-length OOG) or settle with maker real==virtual & curve-bound; length-gated fields fall to safe defaults | PoC-green + code (Calldata.sol: only `end>length` checked) |
| K5-02 | orderHash ⟷ program non-canonical ABI split | SwapVM.sol:99 hash re-encodes decoded order; MakerTraits.program slices the same decoded `order.data`; abi.encode injective | code + AdvAuth (tamper→revert) |
| K5-03 | Dynamic fee provider abuse | Fee.sol: provider = hash-bound program arg; `staticcall`; `require(feeBps≤BPS)`, `to≠0`; maker-pays; no global provider (DEPLOYMENT_MAP) | code |
| K5-04 | Token semantics (FoT/rebasing/ERC777) | Aqua push/pull are CEI (effect before transfer); maker-inventory-scoped; per-order transient lock; taker pays full value | code (Aqua.sol:63-79) + TOKEN_SEMANTICS |
| K5-05 | quote/swap divergence | SwapVM.sol quote uses isStaticContext; fee/Extruction gated by `!isStaticContext`; amounts identical; no settlement in quote | code |
| K5-06 | Stale snapshot across callbacks | SwapVM.sol:239-240 re-reads live balanceIn vs fixed originalAquaBalanceIn+amountIn−amountNetPulled; push=donation (AdvConcentrateHook, campaign 4) | code + PoC |
| K5-07 | Opcode-table divergence (cross-router) | AdvIntegrationRouter: aqua orderHash router-independent, but 2nd-router execution reverts (empty balances); sig bound by EIP-712 domain | PoC-green + code |
| K5-08 | Cross-order shared state "A poisons B" | SHARED_STATE_MAP: no global mutable economic state; `_balances` keyed (maker,app,hash,token); `_reentrancyGuards` per-orderHash transient | code |
| K5-09 | Extruction register-replacement / reentry | AdvIntegrationExtruction (3 tests): can't conjure (pull underflow reverts), can't overcharge taker (validate reverts), within-balance conserves; target is maker-chosen | PoC-green + code |
| K5-10 | CalldataPtr 128-bit packing overlap | only reachable via maker-controlled underflowed program length (index3∈hashed traits) → maker self-harm | code |
| K5-11 | Cross-chain replay (CREATE3 same address) | sig: chainId+verifyingContract in `_hashTypedDataV4`; aqua: balances require per-chain on-chain `ship` | code |
| K5-12 | WETH-unwrap non-WETH tokenOut / dust | SwapVM.sol:275-278 non-WETH `safeWithdrawTo` reverts (self-DoS); WETH.withdraw burns exact amount; Rescuable owner backstop | code (OZ Low "will resolve") |

## Terminal states (why no kill reversed into a finding)

Every integration candidate resolved to one of:
1. **Revert** — cross-router execution, over-large Extruction pull, taker-amount mismatch, non-WETH unwrap, bad signature, foreign token/pair.
2. **Self-harm** — taker waiving own threshold/deadline; maker shipping FoT inventory / a bad fee provider / a bad Extruction target / a wrong-table program.
3. **Conservative settlement** — maker real==virtual, curve-bound movement, value preserved across {taker, maker, feeTo}.

No integration path produced counterparty theft, an authorized≠executed semantic divergence to
the attacker's benefit, cross-order state poisoning, or fund-conjuring.
