# STBL_ESS_CANDIDATES

Deployed ETH ESS (verified source, impls last upgraded 2026-02-20 / Sept-2025 = post-Cyfrin-audit).
Three parallel deep-audit agents + manual review + a Foundry harness (real Issuer/Vault/YieldDistributor
+ mocks). Duplicate firewall: DUP-1 (STBLSCBB-387, JIT/non-time-weighted yield) and DUP-2 (STBLSCBB-386,
withdrawExpired leaves USP unbacked) — both present, both EXCLUDED.

## Result of the core sweep (unprivileged, in-scope)
The core deposit/withdraw/yield/oracle/fee/solvency math is **sound against a purely-unprivileged
attacker** — proven: vault invariant `balance == assetDepositNet + Σfees`; solvency gate never overpays;
rewards protected by lockstep `Σbalance == totalSupply`; rounding protocol-favorable. No unprivileged
critical there. (Residual, non-reportable: CEI/reentrancy in withdrawERC20 — only exploitable if the
asset token has a transfer hook; USDY/OUSG do not.)

## Candidate C1 — `enableYield`/`enableStaking` non-idempotent → cross-user yield theft
- **Root cause (IN SCOPE):** `STBL_LT1_YieldDistributor.enableStaking(id,value)` / `STBL_PT1_...` do a
  blind `balance[id]+=value; totalSupply+=value` with no guard against an already-staked id; the NEW
  post-audit `STBL_(PT1|LT1)_Issuer.enableYield(id)` calls it again on an NFT that `deposit` already
  staked. `stakingStruct.isActive` exists but is never used.
- **Impact (PROVEN in harness `test_enableYield_double_stake_yield_theft`):** re-staking one NFT of two
  equal deposits makes it earn 2/3 vs 1/3 of a distribution (should be 1/2 each) — direct theft from
  honest stakers, plus permanent `totalSupply` inflation (strands rewards after the NFT burns).
- **Trigger:** `SPLITTER_ROLE` (Issuer.enableYield). **Reachability by an unprivileged attacker: PENDING**
  the Splitter/periphery source (does a public `split`/redeem entrypoint call `enableYield` on an
  already-staked NFT?). If yes → HIGH/CRITICAL unprivileged. If Splitter is fully permissioned → latent/hardening.
- **Novelty vs DUPs:** not JIT/time-weighting (DUP-1) — this is a stake-quantity desync from a NEW
  function absent at audit; not DUP-2.

## Candidate C2 — `withdraw(uint256,address)` gutted to `{}` → silent no-op redemption
- **Root cause (IN SCOPE):** post-audit, `STBL_(PT1|LT1)_Issuer.withdraw(uint256 _tokenID, address _sender)`
  changed from `{ iWithdraw(_tokenID,_sender); }` to an empty body `{}`. Public, no revert.
- **Impact (PROVEN in harness `test_empty_2arg_withdraw_is_noop`):** calling it leaves NFT + USP +
  collateral fully intact; the position remains redeemable. A periphery/router that calls the 2-arg
  "redeem on behalf" form now believes the position settled while it is still alive → double-redemption /
  "module A settled, module B redeemable".
- **Trigger:** any contract that calls the 2-arg form. **Reachability: PENDING** the periphery source
  (grep for a 2-arg `issuer.withdraw(...)` call). No in-scope contract calls it. If a live router/Splitter
  does → HIGH/CRITICAL; else latent regression.
- **Novelty vs DUPs:** distinct from DUP-2 (that is withdrawExpired's missing burn, treasury path).

## Gating step
`fetch_splitter.py` resolves Register→Core/YLD and the SPLITTER_ROLE holder(s) and pulls their verified
source. Then grep for callers of the 2-arg `withdraw` and `enableYield` to decide C1/C2 reachability.

## Not-reported (with reasons)
- Deposit `AssetData.limit` not enforced by Issuer (no cap) — risk-param bypass, not theft. Low.
- Missing `_disableInitializers()` in impl constructors — impl left initializable, but OZ UUPS `onlyProxy`
  blocks the selfdestruct-brick; known-low.
- Haircut refunded on normal round-trip (dev note `// look at this in depth`) — protocol revenue leak,
  no attacker gain. Benign/known.
