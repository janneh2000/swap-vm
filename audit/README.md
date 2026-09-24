# Exploit Research Campaign — 1inch Aqua × SwapVM (HackenProof)

Novelty-first, impact-first offensive review. Objective: ONE real, reproducible, unprivileged-taker
security/economic bug in the composition of SwapVM (the programmable-swap VM) and Aqua (the shared-liquidity
ledger). **No submission. No production changes. Local reasoning + user-run PoCs only.**

## Targets (eligible releases, authoritative)
- SwapVM **v1.0.2** `32c687c` → `/home/user/scope-swap-vm`
- Aqua **v1.0.0** `81c26e4` → `/home/user/scope-aqua`
- Live deployed router = **AquaSwapVMRouter** (broadcast/ across Linea/BSC/Arbitrum/Polygon; CREATE3 to
  `0x11111133…AC0De`); Aqua registry = **AquaRouter** (`0x111111…a90a`).
- The working forks `janneh2000/*` are POST-release; Aqua core is identical to v1.0.0, SwapVM main differs
  substantially — see SCOPE.md. All analysis was done on the cloned eligible tags.

## Bottom line
The reachable composition surface (AquaOpcodes + Aqua) is **robustly engineered**; 12 concrete attack
hypotheses were killed with code evidence (KILL_LEDGER.md), 11 load-bearing assumptions resolved
(ASSUMPTION_LEDGER.md). No confirmed finding. The only novel code vs v1.0.1 is the differentially-audited
Fee change, whose second-order interactions are taker-neutral and atomic (RELEASE_DIFF.md).

## Files
- SCOPE.md · THREAT_MODEL.md · RELEASE_DIFF.md — setup, actors, the v1.0.1→v1.0.2 delta.
- INVARIANTS.md · STATE_MACHINE.md · SEMANTIC_BOUNDARIES.md — the model attacked.
- CANDIDATES.md — C-01..C-08 with status.
- ASSUMPTION_LEDGER.md · KILL_LEDGER.md — the disproofs (the real work product).
- DUPLICATE_LEDGER.md — known/audited context + novelty firewall.
- POC_MATRIX.md · HANDOFF.md — PoC plans and the highest-value un-exhausted frames.

## Reproduce the setup
```
git clone --depth1 --branch v1.0.2 https://github.com/1inch/swap-vm scope-swap-vm   # 32c687c
git clone --depth1 --branch v1.0.0 https://github.com/1inch/aqua     scope-aqua      # 81c26e4
git -C scope-swap-vm diff v1.0.1 v1.0.2 -- src/   # → only Fee.sol
```

## Honesty note
This is a heavily-audited target (OZ + Bailsec/Decurity/MixBytes/Theori differential). Per campaign rules the
output of a hunt with no confirmed break is a documented **anti-pattern set** (the defenses that hold) plus a
prioritized list of un-exhausted frames — NOT a manufactured finding. Live-brief scope/known-issues could not
be fetched (egress-blocked); confirm before treating any severity/OOS call as final.
