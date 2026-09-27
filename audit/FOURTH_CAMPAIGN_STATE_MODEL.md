# FOURTH_CAMPAIGN_STATE_MODEL

The state machine of an Aqua balance and a SwapVM swap, derived from the eligible-release
code, used to reason about reinitialization, aliasing, and state-drift attacks (RC-6/RC-3).

Code refs: `scope-aqua/src/Aqua.sol` (ship/dock/pull/push), `scope-swap-vm/src/SwapVM.sol`
(swap/settlement), `libs/Balance.sol` (packing).

---

## 1. Balance cell

`_balances[maker][app][strategyHash][token]` packs `(uint248 amount, uint8 tokensCount)`.

`tokensCount` encodes the lifecycle:

| tokensCount | meaning |
|-------------|---------|
| `0`         | INACTIVE (never shipped, or slot never initialized) |
| `1..0xfe`   | ACTIVE with N tokens in the strategy |
| `0xff` (`_DOCKED`) | DOCKED (closed) |

Key: the cell is keyed by **maker = msg.sender at ship time**, so no actor can create or
mutate a cell under another maker's key via ship.

## 2. Lifecycle transitions

```
        ship (msg.sender=maker)                 dock (msg.sender=maker)
INACTIVE ─────────────────────────▶ ACTIVE ───────────────────────────▶ DOCKED
  (tc=0)   require(tc==0)            (tc=N)   require(tc==N for all)      (tc=0xff)
                                       │
                        pull (msg.sender=app)  amount -= x  (tc unchanged)
                        push (any msg.sender)  amount += x  (require tc>0 && tc!=0xff)
```

Critical invariants read off the code:

- **INV-S1 (ship immutability):** `ship` does `require(balance.tokensCount == 0, StrategiesMustBeImmutable)`.
  An ACTIVE (tc≥1) or DOCKED (tc=0xff) cell **cannot be re-shipped**. Re-initialization of a
  live strategy reverts. (This closes OZ M-1's mechanism: there is no silent reset.)
- **INV-S2 (no return to INACTIVE):** neither `pull` nor `dock` sets tc back to 0. `pull`
  leaves tc unchanged; `dock` sets tc=0xff. So once shipped, a (maker,app,hash,token) slot
  never becomes shippable again → a strategyHash is effectively single-use per (maker,app).
- **INV-S3 (push only into ACTIVE):** `push` requires `tc>0 && tc!=0xff`. You cannot push
  into an inactive or docked strategy.
- **INV-S4 (pull bounded):** `pull` does `balance.store(prevBalance - amount)`; underflow
  reverts. Cannot pull more than the virtual balance.

## 3. strategyHash aliasing

`strategyHash = keccak256(strategy)` in Aqua; in SwapVM the orderHash used for pull/push is
`ctx.query.orderHash`. For Aqua-mode orders these must coincide for settlement to reach the
right cell. AUTHORIZATION_MAP shows they do (orderHash = hash(order), strategy = abi.encode(order)).

Aliasing attack considered: two different `strategy` blobs colliding to the same hash → shared
balance. Requires a keccak256 collision — out of scope / infeasible. Two *legitimately equal*
strategies from different makers do **not** alias: the cell is also keyed by `maker`.

## 4. State-drift attack surface (RC-3) and result

The only state that must stay synchronized is: **virtual balance (Aqua cell amount) vs. real
ERC20 balance settled**. Every fourth-campaign conservation PoC asserts, per swap and per token:

```
makerRealΔ == makerVirtualΔ   (both tokens)
```

Across AdvCanonicalFull (3000 runs, all taker levers), AdvFeeDecay, AdvInvariantsAqua,
AdvSkipConc, AdvConservation — **no drift observed**. `pull` moves real maker→to and
decrements virtual by the same amount; `push` moves real payer→maker and increments virtual by
the same amount; the two always match.

## 5. Multi-swap / time state

Decay carries per-strategy state across swaps (offsets that penalize rapid re-trades).
AdvFeeDecay executes a second, time-warped swap with decay state active and re-asserts
conservation → stateful carry does not break settlement accounting.

**Conclusion:** the state machine admits no reinitialization, no cross-maker aliasing, no
return-to-INACTIVE, and no virtual/real drift. RC-6 and the state-drift portion of RC-3 are
closed.
