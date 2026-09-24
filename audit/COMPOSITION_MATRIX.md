# COMPOSITION MATRIX (live AquaOpcodes; A vs A+B vs B+A where relevant)

Legend: MF = maker-favorable (taker loses to rounding/slippage, correct); CONS = exact settlement
conservation + register==real held; n/t = not in AquaOpcodes / not on live router.

| program | round-trip | conservation | notes |
|---------|-----------|--------------|-------|
| XYC | MF | CONS | baseline |
| Pegged | MF (<=1e24) | CONS | surplus only >=~1e25 (benign, K2-01) |
| Concentrate->XYC | MF | CONS | virtual reserves > real; pull caps at real |
| Decay->XYC | MF | CONS | offsets only worsen taker price |
| Decay->Pegged | MF | CONS | UNTESTED by repo invariants; holds here |
| Concentrate->Decay->XYC | MF | CONS | repo-tested too |
| aquaFee->XYC | MF | CONS | fee lands: taker pays amountIn, maker nets amountIn-fee |
| aquaFee->XYC (skip) | MF | CONS | maker can't cover: fee skipped, register==real, taker exact |
| aquaFee->aquaFee->XYC (stacked) | - | CONS | amountNetPulled accumulates; conserves |
| Concentrate->Decay->Pegged | n/a | n/a | not economically meaningful; not built |
| Extruction->* | n/t-attack | - | target is maker-chosen (called as itself, not delegatecall); maker/strategy risk, documented |
| cross-order nested (swap B in A's callback) | no profit | CONS | per-orderHash lock + per-strategyHash bucket isolation |
| Balances / Invalidators / DutchAuction / TWAP / FeeExperimental-out | n/t | n/t | not in AquaOpcodes (not on deployed router) |

Direction (A/B), exactIn/exactOut, isFirstTransferFromTaker, and useTransferFromAndAquaPush were fuzzed
across the fee compositions; all conserve. Ordering A+B vs B+A for fee↔curve is consistent for sane
programs; only self-authored maker misorderings drift (documented, not taker-exploitable).
