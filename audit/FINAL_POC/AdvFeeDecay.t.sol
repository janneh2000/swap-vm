// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { MockTaker } from "../mocks/MockTaker.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { XYCSwap } from "../../src/instructions/XYCSwap.sol";
import { Decay, DecayArgsBuilder } from "../../src/instructions/Decay.sol";
import { Fee, FeeArgsBuilder } from "../../src/instructions/Fee.sol";

/// @notice Canonical real Aqua program: protocol fee + Decay(MEV protection) + XYC. Real-settlement
/// conservation across the matrix, plus fee<->decay ordering, plus a 2nd swap (decay state active).
contract AdvFeeDecayTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    address feeTo;
    function setUp() public override { super.setUp(); feeTo=makeAddr("feeTo"); }

    function _td(address t, bool exactIn, bool firstFromTaker) internal pure returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:t,isExactIn:exactIn,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:false,isStrictThresholdAmount:false,isFirstTransferFromTaker:firstFromTaker,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }

    // feeFirst=true => [aquaFee][Decay][XYC]; false => [Decay][aquaFee][XYC]
    function _prog(uint32 bps, uint16 period, bool feeFirst) internal view returns (bytes memory){
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory fee = p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(bps, feeTo));
        bytes memory dec = p.build(Decay._decayXD, DecayArgsBuilder.build(period));
        bytes memory xyc = p.build(XYCSwap._xycSwapXD);
        return feeFirst ? bytes.concat(fee, dec, xyc) : bytes.concat(dec, fee, xyc);
    }

    function _assertOneSwap(ISwapVM.Order memory order, bytes32 h, MockTaker t, uint256 amt, bool exactIn, bool firstFromTaker) internal {
        uint256 tkB0=tokenB.balanceOf(address(t)); uint256 tkA0=tokenA.balanceOf(address(t));
        uint256 mkB0=tokenB.balanceOf(maker); uint256 mkA0=tokenA.balanceOf(maker);
        uint256 feB0=tokenB.balanceOf(feeTo);
        (uint248 vB0,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenB));
        (uint248 vA0,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenA));
        try t.swap(order, address(tokenB), address(tokenA), amt, _td(address(t), exactIn, firstFromTaker)) returns(uint256 ai,uint256 ao){
            assertEq(tkB0-tokenB.balanceOf(address(t)), ai, "taker in!=amountIn");
            assertEq(tokenA.balanceOf(address(t))-tkA0, ao, "taker out!=amountOut");
            (uint248 vB1,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenB));
            (uint248 vA1,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenA));
            // register==real (both tokens)
            assertEq(int256(tokenB.balanceOf(maker))-int256(mkB0), int256(uint256(vB1))-int256(uint256(vB0)), "B real!=virtual");
            assertEq(int256(tokenA.balanceOf(maker))-int256(mkA0), int256(uint256(vA1))-int256(uint256(vA0)), "A real!=virtual");
            // global conservation
            uint256 fee = tokenB.balanceOf(feeTo)-feB0;
            assertEq(-int256(ai) + (int256(tokenB.balanceOf(maker))-int256(mkB0)) + int256(fee), int256(0), "B not conserved");
            assertEq(int256(ao) + (int256(tokenA.balanceOf(maker))-int256(mkA0)), int256(0), "A not conserved");
            assertEq(uint256(vA0-vA1), ao, "maker virtual A drop != amountOut");
        } catch { return; }
    }

    function testFuzz_feeDecayXyc(uint32 bps, uint16 period, uint256 balA, uint256 balB, uint256 amt, bool exactIn, bool firstFromTaker, bool feeFirst, uint256 warp) public {
        bps = uint32(bound(bps, 0, 5e8));
        period = uint16(bound(period, 1, 65535));
        balA = bound(balA, 1e12, 1e24); balB = bound(balB, 1e12, 1e24);
        ISwapVM.Order memory order = createStrategy(_prog(bps, period, feeFirst));
        bytes32 h = shipStrategy(order, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33);
        // swap 1
        _assertOneSwap(order, h, t, bound(amt, 1e6, exactIn ? balB : balA/2), exactIn, firstFromTaker);
        // advance time, swap 2 (decay offsets now active) — conservation must still hold
        vm.warp(block.timestamp + bound(warp, 0, 100000));
        _assertOneSwap(order, h, t, bound(amt/2 + 1, 1e6, exactIn ? balB : balA/2), exactIn, firstFromTaker);
    }
}
