# SECOND CAMPAIGN — empirical composition/second-order hunt

Goal: a novel, in-scope, reproducible, real-impact bug in the composition of the LIVE target
(**AquaSwapVMRouter** — the only deployed SwapVM router — + **Aqua/AquaRouter**), beyond the audited
Fee change and the known PeggedSwap findings.

## Tooling (built this session; user authorized installs)
- Foundry 1.5.1 + solc 0.8.30 installed from **GitHub release binaries** (foundry.paradigm.xyz and
  binaries.soliditylang.org are egress-blocked; GitHub release downloads are allowed).
- Deps: OZ 5.4.0 + solidity-utils 6.9.7 (npm registry), forge-std v1.11.0 (git), and **@1inch/aqua
  remapped to the v1.0.0 clone** (`scope-aqua`) so the real Aqua ledger is exercised.
- Harness reuses the repo's own `test/base/AquaSwapVMTest` (real ship/swap/quote) + `ProgramBuilder` to
  build arbitrary AquaOpcodes programs. PoCs in `audit/FINAL_POC/` (mirror of `scope-swap-vm/test/adv/`).
- Run: `forge test --offline --use ~/.svm/0.8.30/solc-0.8.30 --match-path 'test/adv/*' --fuzz-runs 5000`.

## What the deployed router actually exposes (AquaOpcodes)
Controls (jumps/guards/salt/deadline), XYCSwap, XYCConcentrate, Decay, Fee(input variants), PeggedSwap,
Extruction. No Balances/Invalidators/DutchAuction/rate-adjusters/TWAP/FeeExperimental-output on the live
router. Two auth modes; sig mode is impractical here (no Balances to seed reserves), so the live surface is
effectively Aqua-mode.

## Result
Every reachable, taker-exploitable, in-scope invariant tested holds at realistic scales across broad
fuzzing (see FUZZING_RESULTS.md). **No confirmed novel vulnerability.** One anomaly — a wei-level
round-trip surplus in PeggedSwap at absurd (>=~1e25 base-unit) reserves — is a benign, non-amplifiable
rounding artifact within the OZ-reviewed tolerance (KILLED, SECOND_ORDER_LEDGER K2-01). One maker-config
footgun (PeggedSwap config anchors must equal shipped reserves) documented, out of the taker-attack model.
