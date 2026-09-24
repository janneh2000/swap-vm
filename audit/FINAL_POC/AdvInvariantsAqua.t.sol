// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { CoreInvariants } from "../invariants/CoreInvariants.t.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { SwapVM } from "../../src/SwapVM.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { MockTaker } from "../mocks/MockTaker.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { XYCSwap } from "../../src/instructions/XYCSwap.sol";
import { Decay, DecayArgsBuilder } from "../../src/instructions/Decay.sol";
import { PeggedSwap, PeggedSwapArgsBuilder } from "../../src/instructions/PeggedSwap.sol";
import { Fee, FeeArgsBuilder } from "../../src/instructions/Fee.sol";

/// @notice Run the repo's OWN CoreInvariants (symmetry / quote-swap / monotonicity / additivity /
/// rounding-favors-maker / balance-sufficiency) on compositions the repo ships NO invariant test for,
/// AND on the deployed AquaSwapVMRouter + real Aqua settlement path (the repo's invariant suite uses
/// SwapVMRouter + StaticBalances in signature mode). Untested combos: Pegged+Decay, Pegged+Fee(aqua).
contract AdvInvariantsAquaTest is AquaSwapVMTest, CoreInvariants {
    using ProgramBuilder for Program;

    MockTaker internal invTaker;
    address internal feeTo;

    function setUp() public override(AquaSwapVMTest) {
        super.setUp();
        invTaker = new MockTaker(aqua, swapVM, address(this));
        feeTo = makeAddr("feeTo");
    }

    // CoreInvariants hook: real Aqua swap via MockTaker; fund generously so exactOut always has input.
    function _executeSwap(SwapVM _swapVM, ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount, bytes memory takerData)
        internal override returns (uint256 amountIn, uint256 amountOut)
    {
        TokenMock(tokenIn).mint(address(invTaker), amount * 8 + 1e24);
        (amountIn, amountOut) = invTaker.swap(order, tokenIn, tokenOut, amount, takerData);
    }

    function _cfg(bool skipAdd) internal view returns (InvariantConfig memory c) {
        c = _getDefaultConfig();
        // realistic test amounts vs 1e21 reserves
        uint256[] memory amts = new uint256[](3);
        amts[0]=1e18; amts[1]=10e18; amts[2]=50e18;
        c.testAmounts = amts;
        c.symmetryTolerance = 4;          // few-wei curve rounding
        c.roundingToleranceBps = 100;     // 1% (repo default)
        c.skipAdditivity = skipAdd;
        c.exactInTakerData = _td(true);
        c.exactOutTakerData = _td(false);
    }

    function _td(bool exactIn) internal view returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:address(invTaker),isExactIn:exactIn,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:false,isStrictThresholdAmount:false,isFirstTransferFromTaker:false,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }

    function _ship(bytes memory prog, uint256 balA, uint256 balB) internal returns (ISwapVM.Order memory order){
        order = createStrategy(prog);
        shipStrategy(order, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, 1e30); tokenB.mint(maker, 1e30);
    }

    // baseline: plain Pegged (repo tests PeggedSwapInvariants in sig mode; here real Aqua)
    function test_inv_pegged_aqua() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory prog = p.build(PeggedSwap._peggedSwapGrowPriceRange2D, PeggedSwapArgsBuilder.build(PeggedSwapArgsBuilder.Args({x0:1e21,y0:1e21,linearWidth:100e27,rateLt:1,rateGt:1})));
        ISwapVM.Order memory o = _ship(prog, 1e21, 1e21);
        assertAllInvariantsWithConfig(swapVM, o, address(tokenB), address(tokenA), _cfg(false));
    }

    // UNTESTED composition: Pegged + Decay (Decay is stateful -> skip additivity's cross-swap comparison
    // since decay intentionally penalizes the 2nd leg; symmetry/quote-swap/monotonicity/rounding still apply)
    function test_inv_pegged_decay_aqua() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory prog = bytes.concat(
            p.build(Decay._decayXD, DecayArgsBuilder.build(300)),
            p.build(PeggedSwap._peggedSwapGrowPriceRange2D, PeggedSwapArgsBuilder.build(PeggedSwapArgsBuilder.Args({x0:1e21,y0:1e21,linearWidth:100e27,rateLt:1,rateGt:1})))
        );
        ISwapVM.Order memory o = _ship(prog, 1e21, 1e21);
        assertAllInvariantsWithConfig(swapVM, o, address(tokenB), address(tokenA), _cfg(true));
    }

    // UNTESTED (aqua real-settlement): Pegged + aqua protocol fee
    function test_inv_pegged_fee_aqua() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory prog = bytes.concat(
            p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(1e6, feeTo)), // 0.1%
            p.build(PeggedSwap._peggedSwapGrowPriceRange2D, PeggedSwapArgsBuilder.build(PeggedSwapArgsBuilder.Args({x0:1e21,y0:1e21,linearWidth:100e27,rateLt:1,rateGt:1})))
        );
        ISwapVM.Order memory o = _ship(prog, 1e21, 1e21);
        // fee-in changes effective rate; skip spot/symmetry strictness via a looser config
        InvariantConfig memory c = _cfg(false);
        c.skipSpotPrice = true; c.skipSymmetry = true; // fee makes tiny-amount spot checks noisy; keep monotonicity+additivity+quote/swap
        assertAllInvariantsWithConfig(swapVM, o, address(tokenB), address(tokenA), c);
    }
}
