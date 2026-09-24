# ASSUMPTION LEDGER (Hidden-Assumption Falsification Loop)

Resolve each to PROVEN (file:line) / BROKEN (→finding) / TESTING / BLOCKED.

A001 — "Aqua strategyHash == SwapVM orderHash binding holds (both keccak256(abi.encode(order)))."
Status: PROVEN. ship computes keccak256(strategy); SwapVM Aqua hash = keccak256(abi.encode(order));
maker ships strategy = abi.encode(order). Any mismatch → safeBalances reverts (self-DoS only).
Aqua.sol:61, SwapVM.sol:99,148,194.

A002 — "Core binds taker tokenIn/tokenOut to the maker-authorized pair."
Status: BROKEN-as-designed (not itself a finding). MakerTraits.validate only enforces
`tokenIn != tokenOut` (MakerTraits.sol:159-162). Token/direction binding is DELEGATED to the program's
curve instruction, and in Aqua mode `safeBalances` only checks both tokens are *in the strategy* (which
may hold up to 254 tokens). → Feeds H-01 (multi-token strategy pair confusion) and H-02 (curve token
binding). Needs curve read to escalate.

A003 — "opcode >= table length reverts (no wild dispatch); no gaps dispatch to garbage."
Status: PROVEN. Memory dynamic array length trick → OOB index Panic(0x32); unused slots are
`_notInstruction` no-ops. Opcodes.sol:112-119, AquaOpcodes.sol:77-84, VM.sol:130.

A004 — "An order is bound to exactly one router/opcode-table."
Status: PROVEN-conditionally. Sig mode: EIP-712 verifyingContract = router. Aqua mode: Aqua `app` =
router shipped to. BUT orderHash itself encodes NEITHER the router nor the opcode-table version, so a
maker who ships/signs the SAME order to TWO routers gets TWO different executions. Requires maker
opt-in (self-harm) → not a taker attack by itself. Watch for a path that removes the maker-opt-in
requirement. SwapVM.sol:97-108.

A005 — "amountNetPulled can only be inflated by real maker-balance pulls the maker's program dictates."
Status: PROVEN (first-order). Only Fee.sol:271 writes it, only on a landed `AQUA.pull` from maker.
feeBps/to are maker/provider controlled, not taker. This is the audited v1.0.2 area (OZ M-09/Theori#10).
Watch for a SECOND-ORDER path where a non-fee register write, jump, or Extruction sets amountNetPulled,
or where a landed pull's amount != the credit.

A006 — "In Aqua mode the register balanceIn/balanceOut (used for pricing) stays equal to the real Aqua
balance that settlement pulls/pushes against."
Status: TESTING. safeBalances loads them (SwapVM.sol:194). Decay (AquaOpcodes op19) and — on the full
Opcodes router in Aqua mode — Balances (Static/Dynamic) can OVERWRITE the registers. Need to read
Decay + Balances to see if a taker (not maker) can exploit a register↔real divergence. Docs warn makers
to "drop DynamicBalances" for Aqua; AquaOpcodes excludes Balances, so exposure depends on deployed router.

A007 — "The absolute snapshot check `balanceIn >= originalAquaBalanceIn + amountIn - amountNetPulled`
cannot be satisfied without the taker actually paying amountIn (net of fee)."
Status: TESTING. Third-party push / donation satisfies it but is net-negative for the attacker group.
Cross-order nesting hits a different strategyHash slot (no borrow). Need to rule out any same-slot,
attacker-profitable inflation (e.g. a second swap on the SAME orderHash reachable despite the guard,
partial-fill interactions, or a token whose push credits > transferred).

A008 — "Reentrancy guard (per orderHash, held across callbacks) blocks all dangerous re-entry."
Status: TESTING. Blocks re-entry to swap(sameOrder). Allows: swap(otherOrder same maker sharing real
tokens), direct Aqua push, maker hooks / taker callbacks doing arbitrary calls. Need to find a
cross-order or hook interaction that violates an invariant of the in-flight swap.

A009 — "Extruction's returned (nextPC, ctx.swap) cannot be attacker-steered to harm a non-consenting party."
Status: TESTING. target is maker-chosen (strategy risk) but consumes taker args and rewrites ALL
registers + nextPC. Need to read Extruction for whether target/selector is taker-influenced or whether a
static/normal-context confusion exists.

A010 — "quote() and swap() agree on price AND on any security-relevant internal state."
Status: TESTING. Fee.sol documents deliberate quote/swap divergence (fee transfer/pull skipped in
static). Need to check whether any register that survives to settlement (amountNetPulled, amountIn/Out)
can differ between quote and swap in a taker-beneficial way beyond the documented fee case.

A011 — "tokenIn==tokenOut is fully blocked."
Status: PROVEN. MakerTraits.validate:160 reverts tokenIn==tokenOut (post-runLoop, but before any
transfer). Aqua safeBalances with equal tokens would pass but validate kills it before settlement.
(quote path also validates.) Residual: does any state persist/settle BEFORE validate? No — validate runs
before hooks/transfers in both quote and swap. PROVEN.

---
## FINAL RESOLUTIONS (after full read of the live AquaOpcodes set + deps)
- A006 → PROVEN (live). Balances not in AquaOpcodes (can't override registers). Decay only shrinks register
  balanceOut / grows balanceIn (never over-pull). XYCConcentrate/PeggedSwap inflate virtual reserves but the
  tokenOut pull caps at the real bucket (over-inflation → DoS, not theft). Aqua.sol:86; Decay.sol:91-92.
- A007 → PROVEN. Sufficiency check = pushes−nonFeePulls ≥ amountIn; unsatisfiable without taker payment
  (donations net-negative; taker can't pull tokenIn back; cross-order isolated). No underflow (K-12).
- A008 → PROVEN. Per-orderHash guard + per-(maker,app,strategyHash,token) bucket isolation bound all
  nesting to the shared real-wallet cap (FCFS); no virtual-balance cross-contamination. (K-02)
- A009 → BLOCKED-as-designed. Extruction target is maker-chosen (called as itself, not delegatecall); it can
  rewrite all registers incl. amountNetPulled → maker/strategy risk (documented "use at your own risk"), not
  an unprivileged-taker path. (C-07)
- A010 → PROVEN. quote()==swap() amounts; documented divergences are state-write-only (all guarded by
  !isStaticContext), not amount-affecting. (C-05, I12)
- A004 → PROVEN (live). Only AquaSwapVMRouter is deployed (broadcast/), so cross-router same-order execution
  needs the maker to also ship/sign to a second router (self-inflicted).

## Attack-graph status
Every reachable assumption resolves to PROVEN / BLOCKED / DUPLICATE. Un-exhausted (needs egress-blocked audit
texts + Foundry to clear for novelty): PeggedSwap/XYCConcentrate curve-math SECOND-ORDER (most-audited; high
duplicate risk). See HANDOFF.md.
