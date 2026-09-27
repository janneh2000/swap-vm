# FULL_AUDIT_ROOT_CAUSE_MAP

Fourth campaign, Phase 1–2. Every finding across the full 1inch audit archive
(OpenZeppelin v1.0 MVP audit; the v1.0.2 differential set: OZ / Theori / Bailsec /
Decurity / MixBytes), reduced to its **root cause** — the invariant that was broken,
the *class* of bug, and the *primitive* it lived on — so that the campaign attacks the
mechanism, not the label. Historical severities are recorded but explicitly **not
inherited** as a safety signal (per mission: "acknowledged" / "maker-controlled" /
"Medium" are not proof of safety).

Eligible release under test: **SwapVM v1.0.2 (32c687c)**, **Aqua v1.0.0 (81c26e4)**,
deployed router **AquaSwapVMRouter → AquaOpcodes**.

Legend for "Status in eligible release":
- FIXED-VERIFIED = fix present in code AND empirically re-attacked here (see POC_MATRIX).
- FIXED-CODE = fix present in code, read-confirmed, attack surface closed by construction.
- DESIGN = accepted design property (maker-scoped risk); re-tested for *cross-actor* escalation.
- N/A = concerns code not in the eligible release / not in the deployed opcode set.

---

## A. Root-cause CLASSES (the real target)

| Class | Definition | Instructions/primitives it lives on |
|------|------------|-------------------------------------|
| RC-1 Curve math precision / rounding-direction | Rounding must favor the maker (pool); a curve that lets value leak per-swap is drainable by repetition | XYCSwap, XYCConcentrate, PeggedSwap(+Math), Decay |
| RC-2 Invariant non-preservation | The pool's conserved quantity (k, C, L) must be non-decreasing across a swap | XYCConcentrate (L), PeggedSwap (C), XYCSwap (k) |
| RC-3 Balance-accounting drift | Virtual (Aqua) balance must equal the real settled ERC20 movement; fee credit must match tokens actually pulled | SwapVM settlement, Fee `amountNetPulled`, Aqua ledger |
| RC-4 Re-execution / double-settlement | A value-computing step must run at most once per swap | runLoop PC, Controls._jump, all curve/fee recompute guards |
| RC-5 Authorization-context drift | The executed program must be exactly the one the maker authorized (sig or Aqua strategyHash) | SwapVM.hash / orderHash, Aqua strategyHash binding |
| RC-6 State (re)initialization | Shipping/re-shipping a strategy must not silently reset or alias live balances | Aqua.ship/dock, balances packing (amount+tokensCount) |
| RC-7 Hook / callback abuse | Maker hooks and taker callbacks run mid-settlement; they must not move price past bounds or bypass sufficiency to the *counterparty's* benefit | maker pre/post hooks, taker pre-transfer callbacks, Aqua.push |
| RC-8 Fee semantics | Fee must be charged on the correct base, once, and never leave the accounting short | Fee (flat / protocol / aqua-protocol / dynamic), v1.0.2 best-effort collection |

---

## B. Findings → root cause → status

### OZ v1.0 MVP audit

| # | Finding (historical sev) | Root cause | Primitive | Status in eligible release |
|---|--------------------------|-----------|-----------|-----------------------------|
| C-1 | Precision loss in `solve()` quadratic (Critical) | RC-1 | PeggedSwapMath.solve | FIXED-VERIFIED — invariant C non-decreasing across 4×fuzz incl. near-zero A (AdvPeggedInvariant) |
| C-2 | Shared liquidity tracking in multi-token XYCConcentrate (Critical) | RC-2/RC-3 | XYCConcentrate multi-token | N/A (deployed 2D-only `_xycConcentrateGrowLiquidity2D`) + FIXED-VERIFIED for 2D (AdvConcentrateHook, AdvSkipConc) |
| C-3 | Invariant violation & drainage — axis mismatch in PeggedSwap (Critical) | RC-2 | PeggedSwap lt/gt axis | FIXED-VERIFIED — C measured in fixed lt/gt frame, non-decreasing incl. reverse direction & rate asymmetry |
| H-1 | XYCConcentrate records incorrect balances when protocol fee extracted (High) | RC-3/RC-8 | Concentrate ∘ Fee | FIXED-VERIFIED — register==real across fee×concentrate (AdvCanonicalFull, AdvSkipConc) |
| H-2 | Dynamic balance tracking (High) | RC-3 | Aqua balance sync | FIXED-VERIFIED — virtual==real for every swap in every PoC |
| M-1 | Strategy reinitialization via `ship` (Medium) | RC-6 | Aqua.ship | DESIGN (maker-scoped) — re-tested §STATE_MODEL; no cross-maker aliasing |
| M-2 | Unrestricted `Aqua.push` (Medium) | RC-7 | Aqua.push | FIXED-VERIFIED — push credits maker, never authorizes extraction (AdvConcentrateHook proves push→loss for pusher) |
| M-3 | `Calldata.slice` underflow (Medium) | RC-3 | Calldata lib | FIXED-CODE — slice reverts with selector on short args |
| M-4 | Aqua protocol-fee double payment (Medium) | RC-8 | Fee ∘ Aqua | FIXED-VERIFIED — fee counted once, conserved (SETTLEMENT_LEDGER) |
| M-5 | Extruction quote/swap divergence (Medium) | RC-3 | Extruction | DESIGN — Extruction is maker-authored escape hatch, program-bound |
| M-6 | Signing loose non-Aqua strategy (Medium) | RC-5 | sig-mode order | DESIGN — sig mode binds full order incl. program (AUTHORIZATION_MAP) |
| M-7 | Decay stores pre-fee amountIn (Medium) | RC-8/RC-3 | Decay ∘ Fee ordering | FIXED-VERIFIED — fee∘decay∘xyc conserved both orderings (AdvFeeDecay) |
| M-8 | Hook token injection bypasses concentrated price bounds (Medium) | RC-7 | maker hook / taker push | FIXED-VERIFIED as *taker* vector — injection = taker loss, no round-trip profit (AdvConcentrateHook) |
| M-9 | Protocol fee pulled before taker transfer (Medium) | RC-8 | Fee ordering | FIXED-VERIFIED — v1.0.2 best-effort `_tryPullFee`, ProtocolFeeSkipped |
| M-10 | Multiple Fee fee-on-fee (Medium) | RC-8 | Fee ∘ Fee | FIXED-VERIFIED — stacked fees conserve (AdvFeeStack) |
| M-11 | AquaAMM uint16 fees (Medium) | RC-8 | fee encoding | N/A to deployed path / FIXED-CODE (uint32 bps in FeeArgsBuilder) |
| M-12 | Quote not faithful to swap (Medium) | RC-3 | quote vs swap | DESIGN — quote is advisory; swap enforces sufficiency independently |

### v1.0.2 differential set (OZ / Theori / Bailsec / Decurity / MixBytes)

Scope of that differential = **Fee.sol only** (the v1.0.2 change: best-effort protocol-fee
collection). All surviving findings are **Low/Info** and all are **fee-revenue-loss to the
protocol**, never counterparty theft:

| Theme | Root cause | Status |
|-------|-----------|--------|
| Protocol fee silently skipped when maker balance can't cover it (`_tryPullFee` try/catch) | RC-8 | Intended v1.0.2 behavior; emits `ProtocolFeeSkipped`. Re-tested: skipping never breaks taker/maker conservation (AdvSkipConc) |
| Fee griefing by maker (self-deny of protocol revenue) | RC-8 | Maker-scoped, accepted; no counterparty impact |
| `amountNetPulled` credited only on landed pull | RC-3/RC-8 | Correct — prevents phantom-fee accounting drift; verified conserved |

**Conclusion of §B:** every Critical/High root cause is closed *by construction and by
re-attack*; every residual is either maker-scoped (self-harm) or protocol-fee-revenue only.
No historical finding maps to an open counterparty-theft path in the eligible release.

---

## C. Where the auditors' threat model STOPPED (the fourth-campaign frontier)

The differential audits looked only at Fee.sol; the v1.0 audit looked at each instruction
largely in isolation and in **signature mode / StaticBalances**. The frontier this campaign
pushed on:

1. **Deployed Aqua-settlement composition** of the *full* canonical program
   `[aquaProtocolFee][concentrate][xycSwap]` end-to-end (not per-instruction). → AdvCanonicalFull.
2. **Instruction ordering & interpreter re-entry** (backward `_jump` onto a computed step). → AdvBackwardJump.
3. **Cross-instruction invariant carry** (Pegged∘Decay, Pegged∘Fee) under *real* Aqua settlement,
   which the repo's own invariant suite runs only in sig mode. → AdvInvariantsAqua.
4. **Taker-controlled settlement levers** as an exploitation surface: direction × exactIn/exactOut
   × isFirstTransferFromTaker × useTransferFromAndAquaPush × to × callbacks. → every conservation PoC.

Result of pushing that frontier: documented in FOURTH_CAMPAIGN_KILL_LEDGER and
FINAL_FOURTH_CAMPAIGN_ASSESSMENT. **No novel vulnerability survived.**
