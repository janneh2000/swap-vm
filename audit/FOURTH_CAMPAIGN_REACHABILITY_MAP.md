# FOURTH_CAMPAIGN_REACHABILITY_MAP

Every externally-reachable entry point of the deployed system, its caller-authorization, the
state it can mutate, and whether a non-owner (taker / arbitrary third party) can use it to harm
someone else. This is the "who can call what" spine that turns a *theoretical* code property
into a *reachable* (or unreachable) attack.

Deployed surface: **AquaSwapVMRouter** (SwapVM + AquaOpcodes) and **Aqua**.
Refs: `SwapVM.sol`, `Aqua.sol`, `AquaOpcodes.sol`.

---

## 1. SwapVM / router entry points

| Function | Caller | Mutates | Cross-actor harm reachable? |
|----------|--------|---------|------------------------------|
| `swap(order, tin, tout, amount, takerData)` | anyone (taker) | maker's Aqua cell (per authorized curve), taker balances, feeTo | No — bound to shipped strategy (AUTH_MAP); settlement conserves (SETTLEMENT_LEDGER) |
| `quote(...)` (view/static) | anyone | none | No — read-only; advisory (OZ M-12) |
| `hash(order)` (view) | anyone | none | No |

The taker fully controls TakerTraits + callbacks, but the **program and curve are the maker's**
and the funds are the maker's shipped balance. The reentrancy guard is per orderHash.

## 2. Aqua entry points (the externally-callable ledger)

| Function | Caller (`msg.sender`) | Cell touched | Effect | Cross-actor harm? |
|----------|----------------------|--------------|--------|-------------------|
| `ship(app, strategy, tokens, amounts)` | maker (=msg.sender) | `[msg.sender][app][hash][*]` | create ACTIVE cell; `require(tc==0)` immutable | No — writes only under caller's own maker key; cannot touch another maker |
| `dock(app, hash, tokens)` | maker (=msg.sender) | `[msg.sender][app][hash][*]` | close (tc=0xff) | No — own key only |
| `pull(maker, hash, token, amount, to)` | **app** (=msg.sender) | `[maker][msg.sender][hash][token]` | virtual −amount; real maker→to | No — the app key is msg.sender; only the app the maker shipped under (the router) can pull, and only within a swap it is executing. A random EOA calling `pull` uses its *own* address as the app key → reads an empty cell → underflow revert |
| `push(maker, app, hash, token, amount)` | **anyone** | `[maker][app][hash][token]` | virtual +amount; real msg.sender→maker; `require(tc>0 && tc!=0xff)` | **Credits the victim.** The pusher *sends their own tokens to the maker* and increases the maker's balance. Cannot extract. (OZ M-2 "unrestricted push" = donation, not theft) |
| `rawBalances/safeBalances` (view) | anyone | none | No |

### The `pull` authorization subtlety (the thing that makes push-injection safe)

`pull` keys the cell by `[maker][msg.sender][hash][token]`. To pull a maker's funds you must be
the **app** the maker shipped under. The deployed app is the SwapVM router, and the router only
calls `pull` inside `_transferOut`, for `amountOut` computed by the maker's own curve, to the
taker's `to`. An arbitrary third party calling `Aqua.pull` directly is treated as its *own*
app → its cell for the victim is empty → `prevBalance - amount` underflows → revert. **No
foreign pull.**

## 3. The push-injection "sufficiency bypass" — reachable but self-defeating

A taker can call `Aqua.push` in a `preTransferOutCallback` to inflate `balanceOut` so the
router's implicit sufficiency (the pull) succeeds for an `amountOut` larger than the real
reserve. This is *reachable*. But `push` transfers the injected tokens **from the taker to the
maker** and credits the **maker's** cell. The subsequent `pull` sends only `amountOut` back to
the taker. Net: the taker donated the injection to the maker. AdvConcentrateHook confirms taker
net loss and **no round-trip profit** at every fuzzed injection size. Reachable ≠ profitable.

## 4. Hooks / callbacks reachability

| Hook | Set by | Runs as | Can it harm counterparty? |
|------|--------|---------|---------------------------|
| maker pre/postTransferIn/Out hooks | maker (in order) | maker's chosen target | maker-scoped; can only affect maker's own pool (OZ M-8 residual) |
| taker preTransferIn/Out callbacks | taker | taker's contract | can push (donate) or re-enter (guarded); no extraction (AdvNested/AdvConcentrateHook) |

## 5. Reachability conclusion

| Actor | Reachable harmful action? |
|-------|---------------------------|
| Taker | None — bound to maker's curve/funds; every settlement lever conserves; push = self-donation; back-jump can't be crafted (program-bound) |
| Third party (EOA) | None — `push` credits victim; `pull` needs app==msg.sender (empty cell → revert); `ship`/`dock` own-key only |
| Maker | Only self-harm — grief own pool, skip own fee revenue, author a losing curve |

Every reachable entry point resolves to conservative settlement, a revert, or maker self-harm.
No entry point lets one actor extract value from another.
