# FIFTH_TOKEN_SEMANTICS

Phase 8 — what token behavior the architecture assumes, and what breaks if a token violates it.
The question is not "does a weird ERC20 break the maker's own pool" (makers whitelist their
inventory) but "can an unprivileged attacker FORCE a mismatch on an otherwise-legitimate target."

## The four settlement transfers and what they assume

| Op | Code | Assumption |
|----|------|-----------|
| tokenIn push (taker pays) | `AQUA.push`: `balance += amount` then `safeTransferFrom(taker, maker, amount)` | transferred amount == credited amount (no fee-on-transfer) |
| tokenIn transferFrom (sig mode) | `IERC20.safeTransferFrom(taker, receiver, amountIn)` | standard transfer |
| tokenOut pull (maker pays) | `AQUA.pull`: `balance -= amount` then `safeTransferFrom(maker, to, amount)` | maker's real balance ≥ virtual; standard transfer |
| fee pull | `AQUA.pull(maker,…, to)` / `safeTransferFrom(maker, to, fee)` | standard transfer |

Aqua follows **checks-effects-interactions**: `push` credits before the inbound transfer, `pull`
debits before the outbound transfer. So even a token with transfer *hooks* (ERC777) sees a
ledger that is already consistent; a reentrant read during a hook cannot observe a
credited-but-not-transferred or debited-but-not-transferred window in Aqua's own state.

## Non-standard token classes

| Class | Effect | Who is exposed | Unprivileged attack? |
|-------|--------|----------------|----------------------|
| **Fee-on-transfer (tokenIn)** | `push` credits `amount` virtually but the maker's wallet receives `amount−fee`; virtual > real | the MAKER (their strategy over-counts its inventory); later pulls of that token can revert (real short) | No — the taker pays full `amount` (real) and gets curve output; taker gains nothing. Reverts on the maker's next opposite-direction pull rather than extracting. Maker must not ship FoT inventory. |
| **Fee-on-transfer (tokenOut)** | `pull` debits `amount` virtually, maker sends `amount`, taker receives `amount−fee` | the TAKER receives less than amountOut | No — self-affecting; taker's threshold (min-out) still measured against `amountOut` register; taker can set threshold to protect. Not a drain of the maker. |
| **Rebasing** | balances drift after ship | the MAKER's virtual vs real diverge over time | No — maker-scoped inventory risk; no taker lever to force it |
| **ERC777 / transfer hooks** | reentrancy during transfer | reentry blocked on same order (transient lock per orderHash); other orders are normal swaps | No — CEI in Aqua + per-order lock; ERC777 is an unsupported class |
| **Missing/nonstandard return** | handled by `SafeERC20` | — | No |
| **Zero-value transfer** | `amountOut>0` required by `TakerTraits.validate`; `amountIn>0` unless maker `allowZeroAmountIn` | — | No |
| **Same-token pair** | `MakerTraits.validate` reverts tokenIn==tokenOut | — | No |
| **Extreme decimals** | pure scaling in curve math | maker prices it | maker-scoped |

## The key security framing

Every token-semantics mismatch lands on the party that **chose** to expose itself: the maker who
ships a nonstandard token as inventory. An unprivileged taker/third party has **no lever to force
a legitimate maker's standard-token pool into a mismatch** — they cannot change the maker's
tokens (hash-bound to the shipped strategy), and their own payment is a full-value transfer they
fund. FoT/rebasing/ERC777 are the industry-standard "unsupported token" class; the architecture's
CEI ordering and per-order lock keep even those from becoming cross-user theft (they revert or
self-affect). CANDIDATES C5-04 (KILLED).
