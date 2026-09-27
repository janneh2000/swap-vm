# THIRD CAMPAIGN KILL LEDGER (attacking the real audit fixes)

K3A PeggedSwap precision-loss Critical (OZ C-1) re-emergence — KILLED. Stable solve() present
   (PeggedSwapMath.sol:106-112); invariant C non-decreasing over 5000 runs incl. near-zero A. No maker loss.
K3B PeggedSwap axis-mismatch Critical (OZ C-3 / Theori#1 / MixBytes C-1) re-emergence — KILLED.
   parseRatesAndBalances present; reverse-direction + asymmetric-anchor invariant-C holds (5000 runs).
K3C XYCConcentrate multi-token cyclic-arb Critical (OZ C-2 / Nethermind H / MixBytes M-4) — KILLED.
   Concentrate is stateless 2-token in v1.0.2 (no liquidity[orderHash] slot); nothing to corrupt.
K3D Hook token injection bypasses concentrated bounds (OZ M) via TAKER callback — KILLED. Over-extraction
   via injection is pure taker loss; round-trip 4000 runs no gain. Statelessness removed state-corruption.
K3E XYCConcentrate-records-wrong-balances-with-fee (OZ H / Decurity H / Theori#12 / MixBytes M-6) — KILLED.
   Stateless concentrate records nothing; concentrate+fee conserves (AdvSkipConc/AdvFeeStack/AdvInvariantsAqua).
K3F Fee best-effort / amountNetPulled / double-fee / skip (OZ H, v1.0.2 diff) — KILLED (campaign 2 + here).
   Conservation across matrix + skip + stacked; 5 firms found no taker underpayment in v1.0.2 diff.
K3G Maker preTransferInHook reduces taker payment (Nethermind M) — OUT-OF-MODEL. Maker's own hook
   subsidizes takers; taker cannot force a maker to add a subsidizing preTransferInHook. Maker-config.
K3H Decay pre-fee offset (OZ M / Hexens / MixBytes M-3) — NOT theft. Over-compensation favors the MAKER;
   repeated-small-swap "griefing" is DoS-flavored, and the maker can dock. Not taker profit.
K3I Calldata.slice underflow (OZ M / Nethermind) — self-harm/OOG only; program offsets maker-bound, taker
   offsets are taker's own data. Not cross-party (campaign 1 C-06).
K3J Extruction arbitrary target / quote-swap divergence (OZ M / Hexens / Theori#4 / MixBytes M-5) —
   maker-chosen target, plain call (not delegatecall); taker slippage-protected. Maker/strategy risk.
K3K ship/dock multi-call reinit (OZ M / Nethermind M) — maker must reuse hash across pairs (no unique
   salt); XYC cross-pair marginal-neutral; PeggedSwap cross-pair needs config==reserve (maker). Maker-config.

Every fixed Critical/High verified to hold; every live/acknowledged finding is fee-loss / DoS / maker-config
/ maker-strategy-risk — none a novel unprivileged-taker theft.
