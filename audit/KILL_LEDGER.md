# KILL LEDGER (hypotheses disproven with code evidence)

K-01 tokenIn sufficiency underpayment — KILLED. Check = pushes−nonFeePulls ≥ amountIn; taker can't pull
     tokenIn back (pull app=router), donations net-negative, cross-order isolated by strategyHash. SwapVM.sol
     :239-240; Aqua.sol:83-103. (C-01)
K-02 cross-order / cross-app nested-swap value borrow — KILLED. Virtual buckets isolated by
     (maker,app,strategyHash,token) (Aqua.sol:21,67,84,93); nesting competes only for the maker's real wallet
     (FCFS, capped). Reentrancy guard per orderHash (SwapVM.sol:164,213). (I11)
K-03 register↔real divergence (Balances override in Aqua) — KILLED. Balances not in AquaOpcodes; StaticBalances
     require(bal==0) reverts post-Aqua-load; over-inflation → pull underflow (DoS, capped). (C-02)
K-04 transfer-ordering economic divergence — KILLED. Traced both orderings (default vs isFirstTransferFromTaker)
     for exactIn+aqua-fee: identical final accounting (maker +amountIn−fee tokenIn / −amountOut tokenOut; taker
     −amountIn/+amountOut; recipient +fee). SwapVM.sol:205-211. (Specialist 4)
K-05 amountNetPulled inflation / decoupling — KILLED. Only Fee.sol:271 writes it, only on a landed atomic pull;
     feeBps/to maker/provider-controlled; amountNetPulled == tokens removed from ledger. (C-08, RELEASE_DIFF)
K-06 quote() unguarded state mutation — KILLED. All VM state writes guard !isStaticContext; Extruction uses the
     view interface in static mode. (C-05)
K-07 Calldata.slice begin>end giant-slice — KILLED (self-harm). Offsets maker-bound or taker-owns-data; giant
     slices → OOG/no-impact, never cross-party. (C-06)
K-08 opcode wild-dispatch / table drift — KILLED. OOB opcode → Panic; unused slots = _notInstruction no-op;
     per-router binding (domain/app) prevents cross-table execution of one order. (I15, A003)
K-09 multi-token cross-pair arbitrage — KILLED (marginal-neutral) + DUPLICATE (OZ flags multi-token). (C-03)
K-10 tokenIn==tokenOut degenerate — KILLED. validate reverts before any transfer, in both quote and swap
     (MakerTraits.sol:160). (A011)
K-11 ship/dock lifecycle reuse (stale Decay offsets, re-ship) — KILLED. Docked bucket TERMINAL (count=0xFF);
     re-ship blocked; stale per-orderHash offsets unreachable (H can't be re-shipped). (STATE_MACHINE)
K-12 sufficiency-check underflow (amountNetPulled > orig+amountIn) — KILLED. Single input fee ≤ amountIn;
     exactIn restores full amountIn, exactOut grows it ⇒ RHS ≥ originalAquaBalanceIn ≥ 0. (RELEASE_DIFF)
