# STBL_ESS_ARCHITECTURE + VALUE LEDGER (deployed ETH ESS, verified source)

Source: on-chain verified implementations pulled via Etherscan (see STBL_NEW_CODE_TARGET_MATRIX).
All 12 proxies last upgraded 2026-02-20 (Vaults/Issuers) or 2025-09 (YieldDistributors) — i.e. the
current code is **post-Cyfrin-audit** (audit ~Sept 2025). USDY and OUSG implementations are
BYTE-IDENTICAL (config-only differences). PT1 and LT1 are near-identical generic contracts.
BSC USST is unverified on-chain (source unavailable).

## Components (per asset: USDY, OUSG) × tranche (PT1 principal, LT1 liquidity)

- **Issuer** (in scope): user entry. `deposit`, `withdraw`, (LT1) `withdrawExpired`, `enableYield`/`disableYield`.
- **Vault** (in scope): custody + accounting of the RWA collateral. `depositERC20`/`withdrawERC20`
  (issuer-only), `distributeYield` (YIELD_DISTRIBUTION_ROLE), `withdrawFees`/`emergencyWithdraw`.
- **YieldDistributor** (in scope): MasterChef reward-index. `enableStaking`/`disableStaking` (issuer-only),
  `distributeReward` (vault-only), `claim` (permissionless → pays NFT owner).
- **Core** (OUT of scope, impl unavailable): `put`(mint `net` USP + YLD NFT) / `exit`(burn NFT + `net` USP).
- **YLD** (OUT of scope): ERC721 NFT, admin `disableNFT`/`enableNFT` (compliance), `getNFTData`.
- **Register** (OUT of scope): config/roles hub. `fetchAssetData`, `hasRole`, etc.
- **Oracle** (OUT of scope): `fetchPrice()`, `getPriceDecimals()`.

## Value math (verified)
- gross = oracle.forward(assetValue) = price·assetValue/10^pd   (RWA → USD)
- inverse(x) = x·10^pd/price   (USD → RWA), rounds DOWN
- fees = gross·rate/1e9 (deposit, haircut, insurance, withdraw); FEES_CONSTANT=1e9
- **net (USP minted) = gross − depositFee − haircut − insurance**
- staking basis = net + haircut

## Value ledger — DEPOSIT (assetValue A at price P0)
| token | who | Δ |
|---|---|---|
| RWA | user → vault | −A (user), +A (vault) |
| USP | mint to user | +net |
| YLD NFT | mint to user | +1 (id) |
| stake balance[id] | — | +net+haircut ; totalSupply += net+haircut |
Vault tracked: assetDepositGross+=A; assetDepositNet+=A−depositFeeAV−insuranceFeeAV; depositValueUSD+=net+haircut; fees accrue.
Verified vault invariant: **balance == assetDepositNet + Σfees**.

## Value ledger — WITHDRAW (LT1: yieldDuration<age<duration; PT1: age>yieldDuration), price P1
1. claim(id): pending yield (RWA) → NFT owner.
2. vault.withdrawERC20: RWA out = inverse(net+haircut−withdrawFee) to user; withdrawFee stays as fee.
3. disableStaking(id, net+haircut): balance[id]-=…, totalSupply-=…
4. Core.exit(assetID, user, id, net): burn NFT + burn `net` USP from user.
Net user: pays depositFee+insurance+withdrawFee, gets haircut back; USP fully burned. Conserves.

## Value ledger — LT1 withdrawExpired (treasury-only, age>duration)  ← DUP-2 territory
1. if(!isDisabled) claim(id) → yield to NFT owner.
2. vault.withdrawERC20 → RWA to TREASURY.
3. disableStaking.
4. **NO Core.exit / NO NFT burn / NO USP burn.**
⇒ user keeps `net` USP now UNBACKED (collateral went to treasury). **This is DUP-2 (excluded).**

## Post-audit changes (prior→current diff)
1. Vault `distributeYield` gated behind YIELD_DISTRIBUTION_ROLE (hardening fix).
2. Issuer `withdraw(id,sender)` 2-arg body emptied to `{}` (no-op).
3. Issuer `withdrawExpired`: `if (isDisabled)` → `if (!isDisabled)` claim (aligns w/ comment; DUP-2 area).
4. Issuer NEW `enableYield`/`disableYield` (SPLITTER_ROLE) → enable/disableStaking(id, net+haircut) again.
5. Import restructure (Assets/ → asset/, local → @stbl-protocol package).

## Duplicate firewall (hard-excluded root causes)
- DUP-1 (STBLSCBB-387): yield distribution not time-weighted → JIT depositor captures a full period.
- DUP-2 (STBLSCBB-386): withdrawExpired seizes collateral to treasury, leaves USP unbacked.

## Open questions being hunted (agents + manual)
- Staking/reward: NFT transfer vs accrual/claim; totalSupply/index corruption; enable/disableYield desync.
- Deposit/withdraw: unbacked mint / collateral-without-burn distinct from DUP-2; empty 2-arg withdraw callers.
- Oracle/fee/solvency: tracked-var desync vs real balance; haircut accounting (`// look at this in depth`).
- Deposit LIMIT (`AssetData.limit`, `incrementAssetDeposits`) is NOT enforced by the Issuer — bypass (severity TBD).
