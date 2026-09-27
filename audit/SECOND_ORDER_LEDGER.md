# SECOND-ORDER LEDGER (fix -> new invariant -> interaction -> outcome)

K2-01 Fee best-effort skip x sufficiency check. New invariant: amountNetPulled credited only on a landed
  atomic pull. Interaction: skip path + settlement matrix. OUTCOME: PROVEN conserved (5000+4000×2+5000 runs);
  register==real; taker-neutral. Not a bug.
K2-02 amountNetPulled x stacked fees. New invariant: accumulation across nested-runLoop fee wrappers.
  OUTCOME: PROVEN conserved (AdvFeeStack 5000). Not a bug.
K2-03 PeggedSwap maker-favorable rounding x extreme reserves. OUTCOME: wei-level round-trip surplus only at
  >=~1e25 reserves, non-amplifiable -> benign rounding (C2-01). KILLED.
K2-04 PeggedSwap anchor normalization x Aqua-shipped reserves. OUTCOME: mispricing only under maker
  misconfiguration (config != shipped) -> maker footgun (C2-02). Not a taker vuln.
K2-05 Decay (XYC-tuned) x PeggedSwap. New invariant: Decay adjusts reserves before pegged pricing.
  OUTCOME: PROVEN maker-favorable round-trip (Pegged+Decay, warped). Not a bug.
K2-06 Concentrate virtual>real x Aqua real-balance cap. OUTCOME: over-inflation reverts on pull (DoS-bounded,
  never over-extraction); round-trips maker-favorable. Not a bug.
K2-07 per-orderHash reentrancy lock x cross-order nesting (Specialist E). OUTCOME: bucket isolation by
  (maker,app,strategyHash,token) + real-wallet FCFS cap -> no value extraction (AdvNested). Not a bug.
K2-08 orderHash binding x program tampering (Specialist G). OUTCOME: tampered program / foreign token /
  same-token all revert (AdvAuth). Binding holds.
K2-09 register vs real Aqua balance (Specialist D). OUTCOME: every conservation test asserts maker real
  wallet delta == aqua virtual delta; held across all compositions/fees/skip. No divergence.
K2-10 Extruction adversarial (Specialist F). OUTCOME: target is maker-chosen, invoked as a plain external
  call (not delegatecall) so it cannot act AS the router; it can only rewrite THIS swap's registers, which
  is maker/strategy risk (documented "use at your own risk"), not an unprivileged-taker path. Not pursued
  to PoC (no protocol-level primitive for a third party).

Attack graph for the LIVE AquaOpcodes surface: exhausted for unprivileged-taker impact at realistic scale.
