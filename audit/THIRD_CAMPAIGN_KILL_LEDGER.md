# THIRD CAMPAIGN KILL LEDGER

K3-01 "Pegged+Decay violates a core invariant on the real Aqua path" — KILLED. Ran the repo's own
  CoreInvariants (symmetry/quote-swap/monotonicity/rounding-favors-maker/balance-sufficiency) on
  AquaSwapVMRouter+Aqua; PASS. (AdvInvariantsAqua.test_inv_pegged_decay_aqua)
K3-02 "Pegged+aquaFee violates additivity/monotonicity/quote-swap on real Aqua path" — KILLED. PASS.
  (AdvInvariantsAqua.test_inv_pegged_fee_aqua)
K3-03 "Plain Pegged behaves differently under real Aqua settlement than the sig-mode invariant tests" —
  KILLED. Same invariants hold in Aqua mode. (AdvInvariantsAqua.test_inv_pegged_aqua)
K3-04 "Liveness break = fund lock (Critical)" — KILLED by design. Aqua is non-custodial (maker tokens
  stay in the maker wallet; balances are allowances). A bricked strategy is griefing at worst; the maker
  docks + reships. No lockable maker funds exist in the Aqua model. (whitepaper + Aqua.sol)
K3-05 "amountNetPulled consumed by a second accounting instruction on the live router" — KILLED. On
  AquaOpcodes only Fee writes amountNetPulled; no other consumer exists (Opcodes.sol/AquaOpcodes.sol).

(Prior kills K2-01..K2-10 and campaign-1 K-01..K-12 remain valid.)
