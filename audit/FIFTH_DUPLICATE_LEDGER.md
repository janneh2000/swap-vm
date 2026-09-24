# FIFTH_DUPLICATE_LEDGER

Phase 16 — the duplicate firewall for the integration-layer findings. Because **no candidate
survived**, this certifies that each mechanism examined maps to a known finding, a prior-campaign
kill, or a non-issue, and that the two new *observations* (decoder underflow residual,
opcode-table divergence) carry no novel security primitive.

## Corpus

OZ v1.0 MVP audit; v1.0.2 differential set (OZ/Theori/Bailsec/Decurity/MixBytes); campaigns 1–4
ledgers (`audit/FOURTH_CAMPAIGN_*`, `FULL_AUDIT_ROOT_CAUSE_MAP`, `KILL_LEDGER`, etc.); standard
integration issue classes (ABI malleability, opcode/selector confusion, cross-chain replay,
provider/oracle manipulation, FoT/ERC777, stale snapshots).

## Mechanism → prior art

| Fifth-campaign mechanism | Maps to | Novel primitive? | Open? |
|--------------------------|---------|------------------|-------|
| Calldata.slice underflow | OZ **M-3** (Calldata.slice underflow) | No | No (end≤length fixed; begin>end residual non-exploitable) |
| Fee provider trust boundary | OZ M-9 / v1.0.2 differential (Fee.sol) + standard oracle-trust | No | No (maker-scoped, staticcall) |
| Token semantics FoT/ERC777 | standard "unsupported token" class; 1inch norms | No | No (maker-inventory-scoped) |
| quote/swap divergence | documented in-code; OZ M-12 (quote not faithful) family | No | No (amounts identical) |
| Stale snapshot / sufficiency | v1.0.2 `amountNetPulled` design (all differential reviewers) | No | No |
| Cross-order shared state | campaign 2/4 cross-order tests | No | No |
| Extruction escape hatch | OZ M-5 (Extruction quote/swap) family; maker-authored | No | No (maker-scoped, bounded) |
| Order/program binding | OZ M-6 (loose sig) + campaign 4 AUTHORIZATION_MAP | No | No |
| Opcode-table divergence (cross-router) | not a prior finding, but neutralized by the same app-key/EIP-712 binding audits relied on | Observation new; consequence nil | No |
| Cross-chain replay | standard; EIP-712 chainId | No | No |
| WETH unwrap non-WETH | OZ Low ("will resolve") | No | Known-Low, self-DoS |

## The two new observations, adjudicated

1. **Calldata.slice `begin>end` residual** — the audited M-3 fix added `end≤length`; the
   remaining `begin>end` underflow is a *robustness* gap, not a new exploitable primitive (all
   taker paths self-DoS / safe-default; maker paths hash-bound). Duplicate of the M-3 area.
2. **Opcode-table divergence between routers** — a real structural observation not spelled out in
   prior findings, but it produces **no security consequence** because order↔router binding
   (Aqua app-key; sig EIP-712 domain) prevents wrong-router execution. Novelty of *observation* ≠
   novelty of *vulnerability*; there is no vulnerability to deduplicate.

## Verdict

No novel, in-scope, open integration finding exists to deduplicate. The firewall has nothing to
pass through. Any future integration mechanism must be checked against this corpus before being
treated as novel.
