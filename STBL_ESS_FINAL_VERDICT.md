# STBL ESS / Redemptions — Final Hunt Verdict

**Scope:** the 12 deployed, in-scope ESS/redemption contracts (PT1/LT1 × {Issuer, Vault,
YieldDistributor} for USDY + OUSG, plus BSC USST). Attacker model: **purely unprivileged**
(no admin / issuer / vault-operator / oracle / SPLITTER role, no `_msgSender()` spoof).
Goal: a **novel, in-scope, reachable, unprivileged, reproducible CRITICAL**, not a duplicate of
the two supplied prior reports (DUP-1 STBLSCBB-387, DUP-2 STBLSCBB-386) nor of the public audits
(Cyfrin STBL / ESS-Redemptions, Hashlock, Nethermind).

## Verdict

**No reachable, unprivileged CRITICAL is rooted in the 12 in-scope contracts as currently
deployed and configured.** This is the honest result of a full review against the *actual*
on-chain verified source (implementations resolved through the proxies and pinned), the real
Core / YLD / Register periphery, three deep-audit passes, manual review, and a Foundry harness
built on the real Issuer / Vault / YieldDistributor (6 passing tests). A real "nothing live"
is reported rather than an inflated Critical.

## What was proven sound (unprivileged)

Empirically, against the real deployed source (harness `poc/Harness.t.sol`, 6/6 passing):

| Property | Test | Result |
|---|---|---|
| Deposit→withdraw conserves value; USP fully burned; only fees retained | `test_deposit_withdraw_conservation` | net USP 1047.28 for 1000 RWA; vault keeps 3 fee tokens |
| Price **+2×** → no appreciation capture / no over-payment | `test_price_rise_no_overpayment` | user gets 498.5 tokens (same USD), < 1000 deposited |
| Price **−50%** → global solvency gate **freezes** withdraw | `test_price_drop_triggers_solvency_freeze` | reverts (no free extraction) |
| Pooled vault, first-mover cannot drain others | `test_pooled_no_cross_user_drain` | A exits first; B still fully redeemable |

Reasoned + reviewed sound as well: vault invariant `balance == assetDepositNet + Σfees` holds
per-operation at any price; oracle forward/inverse round protocol-favorably; USDY/OUSG are both
18-decimal so decimal conversions are no-ops; deposit limit **is** enforced (at `Core.put` via
`isDepositLimitReached`); reward index (`rewardIndex += reward·1e18/totalSupply`) is standard
MasterChef with lockstep `Σbalance == totalSupply` under normal deposit/withdraw; `claim` only
pays legitimately-accrued yield to `ownerOf(id)`; `withdrawFees`/`emergencyWithdraw` are
permissionless but pay only the treasury (no attacker gain; `emergencyWithdraw` also needs
admin `EMERGENCY_STOP`). Every permissionless entrypoint was enumerated; none yields attacker
profit.

## The two genuine, novel, in-scope defects — both DORMANT

Both are **new post-audit code** (confirmed by prior→current diff: the audited version had a
*functional* 2-arg withdraw and **no** `enableYield`/`disableYield`), so both are novel vs the
public audits and distinct from DUP-1 (JIT/non-time-weighted yield) and DUP-2 (`withdrawExpired`
unbacked USP). Neither is reachable by an unprivileged attacker in the live deployment.

### C1 — `enableStaking`/`enableYield` non-idempotent → cross-user yield theft
- **Root cause (IN SCOPE):** `STBL_(LT1|PT1)_YieldDistributor.enableStaking(id,value)` does a
  blind `balance[id]+=value; totalSupply+=value` with no already-staked guard
  (`stakingStruct.isActive` exists but is never read/written). The new post-audit
  `STBL_(LT1|PT1)_Issuer.enableYield(id)` calls it again on an NFT that `deposit` already staked.
- **Impact (PROVEN, `test_enableYield_double_stake_yield_theft`):** re-staking one of two equal
  deposits makes it earn **66.67 vs 33.33** of a distribution (fair = 50/50) — direct theft from
  honest stakers, plus permanent `totalSupply` inflation that strands rewards after burn.
- **Why not live:** `enableYield` is gated `hasRole(SPLITTER_ROLE, _msgSender())`.
  **SPLITTER_ROLE has zero holders on-chain** (verified: no `RoleGranted` log for the role;
  `STBL_Register` uses plain `AccessControlUpgradeable`, grantable only by `DEFAULT_ADMIN_ROLE`),
  and **no in-scope or periphery contract calls `enableYield`**. Unreachable unprivileged.
  There is also no unprivileged way to double-call `enableStaking`: it is `isIssuer`, and
  `iDeposit` always uses a fresh monotonic `nftCtr` id.

### C2 — 2-arg `withdraw(uint256,address)` gutted to `{}` → silent no-op redemption
- **Root cause (IN SCOPE):** post-audit the body changed from `iWithdraw(_tokenID,_sender)` to
  an empty `{}`. Public, no revert.
- **Impact (PROVEN, `test_empty_2arg_withdraw_is_noop`):** the call leaves NFT + USP + collateral
  fully intact; a periphery/router that calls the 2-arg "redeem on behalf" form believes the
  position settled while it is still alive.
- **Why not live:** **no in-scope or periphery contract calls the 2-arg form** (the only external
  "redeem-on-behalf" integrator would be a Splitter, which is neither deployed nor role-granted).
  An unprivileged attacker gains nothing by calling it. Latent footgun, not a live critical.

## Items examined and set aside (with reason)
- **CEI / reentrancy in `withdrawERC20`** (transfer before state update): only exploitable if the
  asset token has a transfer hook. USDY/OUSG have none; adding a hooking asset is a privileged
  config action. Not currently exploitable; also audit-101 (likely known). Not reportable.
- **2-arg `deposit(uint256,address)`**: pulls RWA from `_sender` and mints USP+NFT to the same
  `_sender` — a *forced deposit* requiring the victim's standing vault approval; victim receives
  equivalent value. Griefing at most. Low, not critical.
- **Haircut refunded on a normal round-trip** (`// look at this in depth`): protocol keeps only
  deposit+insurance+withdraw fees; haircut is returned to the withdrawer. No attacker gain.
- **YLD `_update` reverts on `isDisabled` regardless of `to`**: burning an admin-disabled NFT
  reverts, contradicting its own comment — but `disableNFT` is `DEFAULT_ADMIN_ROLE`. Not
  unprivileged; also the NFT/YLD contract is out of scope as a root cause.
- **BSC USST (0x1171ce…)**: source unverified on-chain; cannot audit without bytecode work.

## Bottom line for submission
Submitting C1 or C2 as "Critical" would be inflation: both are unreachable by an unprivileged
actor in the current deployment (SPLITTER_ROLE unassigned; no 2-arg-withdraw caller). Their honest
standing is **latent post-audit regression / defense-in-depth** — worth reporting to the team as
hardening (add an `isActive` idempotency guard to `enableStaking`; restore or explicitly `revert`
the 2-arg `withdraw`), but **not a live unprivileged Critical**. No fabricated finding is
submitted.
