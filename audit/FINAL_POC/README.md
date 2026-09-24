# FINAL_POC — adversarial Foundry harness (second campaign)

Runnable against the eligible releases. Setup used in this session:

```
# eligible tags
git clone --depth1 --branch v1.0.2 https://github.com/1inch/swap-vm scope-swap-vm   # 32c687c
git clone --depth1 --branch v1.0.0 https://github.com/1inch/aqua     scope-aqua      # 81c26e4
# deps (registry: OZ 5.4.0, solidity-utils 6.9.7; git: forge-std v1.11.0; @1inch/aqua -> scope-aqua)
# solc 0.8.30 + foundry 1.5.1 installed from GitHub release binaries (paradigm host is egress-blocked)
# place these *.t.sol in scope-swap-vm/test/adv/ and run:
forge test --offline --use ~/.svm/0.8.30/solc-0.8.30 --match-path 'test/adv/*' --fuzz-runs 5000 -vv
```

Deployed router == AquaSwapVMRouter (AquaOpcodes). Tests build raw programs via ProgramBuilder + _opcodes()
and drive real Aqua ship/swap through the repo's own AquaSwapVMTest base.

| file | what it proves |
|------|----------------|
| AdvComposition.t.sol | round-trip no-profit: XYC, Pegged, Pegged+Decay (sanity) |
| AdvFuzz.t.sol | fuzz round-trip (Pegged, Pegged+Decay) + XYC conservation |
| AdvConservation.t.sol | exact settlement conservation w/ fee across matrix: dir × exactIn/Out × firstFromTaker × {callback, useTransferFromAndAquaPush}; asserts register==real + global token conservation |
| AdvNested.t.sol | malicious taker nests swap(B) inside swap(A)'s callback (cross-order, same maker) — no value extraction |
| AdvSkipConc.t.sol | v1.0.2 best-effort fee SKIP path conservation (maker can't cover fee) + XYCConcentrate round-trip at price boundaries (+Decay) |
| AdvFeeStack.t.sol | two stacked aqua protocol fees (distinct recipients) — exact conservation + register==real |
| AdvAuth.t.sol | authorization binding: cannot strip fee instruction / use foreign token / same-token (all revert) |
| AdvBoundary.t.sol | Pegged(+Decay,+rate/decimal asymmetry) round-trip maker-favorable at realistic scale (<=1e24) |
| AdvPeggedMin.t.sol | scale-scan + amplification: characterizes the benign extreme-scale (>=~1e25) rounding surplus (KILLED) |

All pass at realistic scales. No confirmed novel taker-exploitable bug.
