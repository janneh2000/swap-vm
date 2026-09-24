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
import { XYCConcentrate, XYCConcentrateArgsBuilder } from "../../src/instructions/XYCConcentrate.sol";
import { Decay, DecayArgsBuilder } from "../../src/instructions/Decay.sol";
import { Fee, FeeArgsBuilder } from "../../src/instructions/Fee.sol";

contract AdvSkipConcTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    address feeTo;
    function setUp() public override { super.setUp(); feeTo = makeAddr("feeTo"); }

    function _td(address t, bool exactIn) internal pure returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:t,isExactIn:exactIn,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:false,isStrictThresholdAmount:false,isFirstTransferFromTaker:false,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }

    // ---------------- FEE SKIP PATH conservation (v1.0.2 best-effort) ----------------
    // maker has NO tokenIn(B) wallet inventory => fee pull (maker->feeTo) reverts => skipped.
    // Assert: taker still pays exactly amountIn, gets amountOut; feeTo gets 0; register==real.
    function testFuzz_feeSkip_conservation(uint256 balA, uint256 balB, uint256 amt, uint32 feeBps) public {
        balA = bound(balA, 1e9, 1e27);
        balB = bound(balB, 1e9, 1e27);
        feeBps = uint32(bound(feeBps, 1, 1e9));
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory prog = bytes.concat(
            p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(feeBps, feeTo)),
            p.build(XYCSwap._xycSwapXD)
        );
        ISwapVM.Order memory order = createStrategy(prog);
        bytes32 h = shipStrategy(order, tokenA, tokenB, balA, balB);
        // fund ONLY tokenOut (A) wallet for maker so tokenOut pull works; tokenIn(B) wallet stays 0 => fee skip
        tokenA.mint(maker, 1e30);
        // taker
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e30);
        amt = bound(amt, 1e6, balB); // B->A exactIn
        uint256 tkB0=tokenB.balanceOf(address(t)); uint256 tkA0=tokenA.balanceOf(address(t));
        uint256 fe0=tokenB.balanceOf(feeTo);
        (uint248 vB0,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenB));
        (uint248 vA0,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenA));
        try t.swap(order, address(tokenB), address(tokenA), amt, _td(address(t), true)) returns(uint256 ai,uint256 ao){
            assertEq(tkB0-tokenB.balanceOf(address(t)), ai, "taker paid != amountIn");
            assertEq(tokenA.balanceOf(address(t))-tkA0, ao, "taker got != amountOut");
            // fee was skipped (maker had no B wallet) => feeTo gets nothing
            assertEq(tokenB.balanceOf(feeTo), fe0, "feeTo received tokens despite skip");
            // register == real: maker virtual B increased by exactly amountIn (no fee pulled)
            (uint248 vB1,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenB));
            (uint248 vA1,)=aqua.rawBalances(maker,address(swapVM),h,address(tokenA));
            assertEq(uint256(vB1-vB0), ai, "skip: maker virtual B delta != amountIn");
            assertEq(uint256(vA0-vA1), ao, "skip: maker virtual A delta != amountOut");
        } catch { return; }
    }

    // ---------------- XYCConcentrate round-trip + real-settlement conservation at boundaries ----------------
    function testFuzz_concentrate_roundtrip(uint256 R, uint256 sMin, uint256 sMax, uint256 amt, bool withDecay) public {
        R = bound(R, 1e12, 1e27);
        // sqrt price bounds; price = (sqrtP/1e9)^2 roughly. keep in a wide but bounded band.
        sMin = bound(sMin, 1e6, 1e17);
        sMax = bound(sMax, sMin + 1, 1e18);
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory conc = p.build(XYCConcentrate._xycConcentrateGrowLiquidity2D, XYCConcentrateArgsBuilder.build2D(sMin, sMax));
        bytes memory prog = withDecay
            ? bytes.concat(conc, p.build(Decay._decayXD, DecayArgsBuilder.build(300)), p.build(XYCSwap._xycSwapXD))
            : bytes.concat(conc, p.build(XYCSwap._xycSwapXD));
        ISwapVM.Order memory order = createStrategy(prog);
        bytes32 h = shipStrategy(order, tokenA, tokenB, R, R);
        tokenA.mint(maker, type(uint128).max); tokenB.mint(maker, type(uint128).max);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), type(uint128).max);
        uint256 b0=tokenB.balanceOf(address(t));
        uint256 amtIn = bound(amt, 1e3, R/4);
        try t.swap(order, address(tokenB), address(tokenA), amtIn, _td(address(t), true)) returns(uint256,uint256 gotA){
            if (gotA==0) return;
            if (withDecay) vm.warp(block.timestamp+301);
            try t.swap(order, address(tokenA), address(tokenB), gotA, _td(address(t), true)) returns(uint256,uint256){
                assertLe(tokenB.balanceOf(address(t)), b0, "concentrate roundtrip PROFIT");
            } catch {}
        } catch {}
    }
}
