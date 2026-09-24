# FIFTH_SHARED_STATE_MAP

Phase 10 — every piece of mutable state that more than one order/actor touches, and whether
"order A changes shared state that order B trusts, to A's benefit" is reachable.

## Inventory of mutable state

| State | Location | Scope / key | Shared across orders? | Attacker-influenceable to harm another order? |
|-------|----------|-------------|-----------------------|-----------------------------------------------|
| `_balances[maker][app][hash][token]` | Aqua | per (maker, router, strategyHash, token) | **No** — a strategyHash is one maker's one strategy | No. `push` only credits; `pull` needs `app==msg.sender` (the router, only during that order's swap); `ship` requires `tokensCount==0` (immutable); keyed by maker so no cross-maker write |
| `_reentrancyGuards[orderHash]` | SwapVM | per orderHash, **transient** | No — per order | No — lock/unlock within one swap; different order = different slot |
| EIP-712 domain (`_cachedDomainSeparator`, etc.) | EIP712 | immutable after ctor (or recomputed on chainId change) | read-only | No |
| `AQUA` address | SwapVM | immutable | read-only | No |
| Rescuable `owner` | Rescuable | privileged | — | owner-only; not swap-path |
| Decay per-strategy offsets | via Aqua balances / strategy | per strategyHash | No | maker-scoped (its own strategy's MEV penalty) |
| Fee provider state | external maker-chosen contract | per provider | only if two makers name the same provider | provider is staticcall-read; any shared-state logic is out-of-scope and harms the maker who chose it (FEE_PROVIDER_ANALYSIS) |
| Token ERC20 balances | tokens | global | yes (it's an AMM) | this IS the market; bounded by curve conservation (campaigns 1–4) |

## The specific "A poisons B" hunt

- **No global counters, caches, or registries** in SwapVM or Aqua that a swap writes and another
  swap reads. The router holds no per-swap storage beyond the transient per-order lock.
- **Balances are strictly partitioned** by (maker, app, hash, token). Order A (maker M1) cannot
  write order B's cell (maker M2) — `ship`/`push`/`pull`/`dock` all key on a maker the caller
  cannot spoof (`ship`/`dock` use `msg.sender`; `pull` uses `msg.sender` as app; `push` credits
  the named maker with the pusher's own tokens).
- **Transient lock is per-order**, so cross-order reentrancy is possible but is just an
  independent, separately-conservation-checked swap — no shared mutable state carries A's effect
  into B (AdvNested, campaign 4; Extruction cross-order reentry, CALLBACK_BOUNDARY).
- **Per-maker vs per-order confusion:** checked — balances are per (maker, app, **hash**), and the
  hash is the strategy, so per-strategy. There is no field mistakenly keyed per-maker that an
  attacker could alias across a victim maker's strategies, nor a per-app value treated as
  per-maker.

## Verdict

There is no shared, mutable, economically-meaningful state (other than the token balances the
AMM curve already governs) that one order can write and another order trusts. The "A influences
B" primitive is not present. CANDIDATES C5-08 (KILLED).
