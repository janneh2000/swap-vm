// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";

import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { MockTaker } from "../mocks/MockTaker.sol";

import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { XYCSwap } from "../../src/instructions/XYCSwap.sol";
import { Fee, FeeArgsBuilder } from "../../src/instructions/Fee.sol";

/// @notice Fee x Fee stacking: two aqua protocol fees (distinct recipients) + XYC. Checks exact conservation
/// and that amountNetPulled accumulation across stacked fees keeps register==real and taker exact.
contract AdvFeeStackTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    address feeTo1; address feeTo2;
    function setUp() public override { super.setUp(); feeTo1=makeAddr("f1"); feeTo2=makeAddr("f2"); }

    function _td(address t, bool exactIn) internal pure returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:t,isExactIn:exactIn,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:false,isStrictThresholdAmount:false,isFirstTransferFromTaker:false,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }

    function testFuzz_stacked_fees_conservation(uint256 balA, uint256 balB, uint256 amt, uint32 bps1, uint32 bps2, bool exactIn) public {
        balA = bound(balA, 1e12, 1e27);
        balB = bound(balB, 1e12, 1e27);
        bps1 = uint32(bound(bps1, 0, 5e8)); // up to 50% each
        bps2 = uint32(bound(bps2, 0, 5e8));
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory prog = bytes.concat(
            p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(bps1, feeTo1)),
            p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(bps2, feeTo2)),
            p.build(XYCSwap._xycSwapXD)
        );
        ISwapVM.Order memory order = createStrategy(prog);
        bytes32 h = shipStrategy(order, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33);
        amt = bound(amt, 1e6, exactIn ? balB : balA/2);

        // tokenIn = B, tokenOut = A
        uint256 tkB0=tokenB.balanceOf(address(t)); uint256 tkA0=tokenA.balanceOf(address(t));
        uint256 mkB0=tokenB.balanceOf(maker); uint256 mkA0=tokenA.balanceOf(maker);
        uint256 f1B0=tokenB.balanceOf(feeTo1); uint256 f2B0=tokenB.balanceOf(feeTo2);
        (uint248 vB0,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenB));
        (uint248 vA0,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenA));

        try t.swap(order, address(tokenB), address(tokenA), amt, _td(address(t), exactIn)) returns(uint256 ai,uint256 ao){
            // taker exact
            assertEq(tkB0-tokenB.balanceOf(address(t)), ai, "taker paid != amountIn");
            assertEq(tokenA.balanceOf(address(t))-tkA0, ao, "taker got != amountOut");
            // fees paid in tokenB (tokenIn) from maker to recipients
            uint256 fee1 = tokenB.balanceOf(feeTo1)-f1B0;
            uint256 fee2 = tokenB.balanceOf(feeTo2)-f2B0;
            // register==real for maker tokenB: virtual delta == real wallet delta
            (uint248 vB1,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenB));
            (uint248 vA1,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenA));
            int256 realB = int256(tokenB.balanceOf(maker))-int256(mkB0);
            int256 virtB = int256(uint256(vB1))-int256(uint256(vB0));
            assertEq(realB, virtB, "maker tokenB real!=virtual (register divergence)");
            int256 realA = int256(tokenA.balanceOf(maker))-int256(mkA0);
            int256 virtA = int256(uint256(vA1))-int256(uint256(vA0));
            assertEq(realA, virtA, "maker tokenA real!=virtual");
            // global tokenB conservation: taker(-ai) + maker(realB) + fee1 + fee2 == 0
            int256 sumB = -int256(ai) + realB + int256(fee1) + int256(fee2);
            assertEq(sumB, int256(0), "tokenB not conserved globally");
            // global tokenA conservation: taker(+ao) + maker(realA) == 0
            assertEq(int256(ao)+realA, int256(0), "tokenA not conserved globally");
            // maker virtual tokenA drops by exactly amountOut
            assertEq(uint256(vA0-vA1), ao, "maker virtual A drop != amountOut");
        } catch { return; }
    }
}
