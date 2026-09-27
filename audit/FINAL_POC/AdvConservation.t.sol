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
import { Decay, DecayArgsBuilder } from "../../src/instructions/Decay.sol";
import { Fee, FeeArgsBuilder } from "../../src/instructions/Fee.sol";

/// @notice Exact settlement conservation with fees across the full taker-controlled settlement matrix.
/// Invariants (no fee-math replication needed):
///  (1) taker position change == (-amountIn tokenIn, +amountOut tokenOut)
///  (2) maker REAL wallet delta == maker AQUA VIRTUAL delta  (register == real), both tokens
///  (3) global token conservation: sum of all real deltas per token == 0
contract AdvConservationTest is AquaSwapVMTest {
    using ProgramBuilder for Program;

    address feeTo;

    function setUp() public override { super.setUp(); feeTo = makeAddr("feeTo"); }

    struct Snap { uint256 tkA; uint256 tkB; uint256 mkA; uint256 mkB; uint256 feA; uint256 feB; uint256 vA; uint256 vB; }

    function _snap(address t, bytes32 h) internal view returns (Snap memory s) {
        s.tkA = tokenA.balanceOf(t); s.tkB = tokenB.balanceOf(t);
        s.mkA = tokenA.balanceOf(maker); s.mkB = tokenB.balanceOf(maker);
        s.feA = tokenA.balanceOf(feeTo); s.feB = tokenB.balanceOf(feeTo);
        (uint248 va,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA));
        (uint248 vb,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenB));
        s.vA = va; s.vB = vb;
    }

    function _prog(uint32 feeBps) internal view returns (bytes memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory feePart = feeBps > 0
            ? p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(feeBps, feeTo))
            : bytes("");
        return bytes.concat(feePart, p.build(XYCSwap._xycSwapXD));
    }

    function _order(bytes memory program, uint256 balA, uint256 balB) internal returns (ISwapVM.Order memory order, bytes32 h) {
        order = createStrategy(program);
        h = shipStrategy(order, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);
    }

    function _td(address t, bool exactIn, bool firstFromTaker, bool useTFAP, bool hasCb) internal pure returns (bytes memory) {
        return TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: t, isExactIn: exactIn, shouldUnwrapWeth: false,
            hasPreTransferInCallback: hasCb, hasPreTransferOutCallback: false,
            isStrictThresholdAmount: false, isFirstTransferFromTaker: firstFromTaker, useTransferFromAndAquaPush: useTFAP,
            threshold: "", to: address(0), deadline: 0,
            preTransferInHookData: "", postTransferInHookData: "", preTransferOutHookData: "", postTransferOutHookData: "",
            preTransferInCallbackData: "", preTransferOutCallbackData: "", instructionsArgs: "", signature: ""
        }));
    }

    // callback mode (MockTaker pushes tokenIn); returns nothing, asserts conservation
    function _runCallback(uint32 feeBps, uint256 balA, uint256 balB, uint256 amount, bool exactIn, bool firstFromTaker) internal {
        (ISwapVM.Order memory order, bytes32 h) = _order(_prog(feeBps), balA, balB);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33); // plenty of tokenIn (B->A)
        Snap memory a = _snap(address(t), h);
        try t.swap(order, address(tokenB), address(tokenA), amount, _td(address(t), exactIn, firstFromTaker, false, true))
            returns (uint256 amtIn, uint256 amtOut)
        {
            Snap memory b = _snap(address(t), h);
            _assertConservation(a, b, amtIn, amtOut);
        } catch { return; }
    }

    // useTransferFromAndAquaPush mode (EOA approves router)
    function _runTFAP(uint32 feeBps, uint256 balA, uint256 balB, uint256 amount, bool exactIn, bool firstFromTaker) internal {
        (ISwapVM.Order memory order, bytes32 h) = _order(_prog(feeBps), balA, balB);
        address t = makeAddr("eoaTaker");
        tokenB.mint(t, 1e33);
        vm.prank(t); tokenB.approve(address(swapVM), type(uint256).max);
        Snap memory a = _snap(t, h);
        vm.prank(t);
        try swapVM.swap(order, address(tokenB), address(tokenA), amount, _td(t, exactIn, firstFromTaker, true, false))
            returns (uint256 amtIn, uint256 amtOut, bytes32)
        {
            Snap memory b = _snap(t, h);
            _assertConservation(a, b, amtIn, amtOut);
        } catch { return; }
    }

    // tokenIn = B, tokenOut = A for these runs
    function _assertConservation(Snap memory a, Snap memory b, uint256 amtIn, uint256 amtOut) internal pure {
        // (1) taker: -amtIn tokenB, +amtOut tokenA
        assertEq(a.tkB - b.tkB, amtIn, "taker tokenIn(B) != amountIn");
        assertEq(b.tkA - a.tkA, amtOut, "taker tokenOut(A) != amountOut");
        // (2) register == real for the maker, both tokens
        // maker real tokenB (in) delta
        int256 mkB = int256(b.mkB) - int256(a.mkB);
        int256 vB  = int256(b.vB) - int256(a.vB);
        assertEq(mkB, vB, "maker tokenIn(B): real wallet delta != aqua virtual delta");
        int256 mkA = int256(b.mkA) - int256(a.mkA);
        int256 vA  = int256(b.vA) - int256(a.vA);
        assertEq(mkA, vA, "maker tokenOut(A): real wallet delta != aqua virtual delta");
        // (3) global conservation per token: taker + maker + feeTo deltas == 0
        int256 sumB = (int256(b.tkB) - int256(a.tkB)) + (int256(b.mkB) - int256(a.mkB)) + (int256(b.feB) - int256(a.feB));
        int256 sumA = (int256(b.tkA) - int256(a.tkA)) + (int256(b.mkA) - int256(a.mkA)) + (int256(b.feA) - int256(a.feA));
        assertEq(sumB, int256(0), "tokenB not conserved globally");
        assertEq(sumA, int256(0), "tokenA not conserved globally");
        // (2b) maker tokenOut(A) virtual must drop by exactly amountOut
        assertEq(uint256(-vA), amtOut, "maker tokenOut(A) virtual drop != amountOut");
    }

    // ---- fuzz the whole matrix ----
    function testFuzz_conservation_callback(uint32 feeBps, uint256 balA, uint256 balB, uint256 amount, bool exactIn, bool firstFromTaker) public {
        feeBps = uint32(bound(feeBps, 0, 1e9));
        balA = bound(balA, 1e12, 1e24); balB = bound(balB, 1e12, 1e24);
        amount = bound(amount, 1e6, exactIn ? balB : balA / 2);
        _runCallback(feeBps, balA, balB, amount, exactIn, firstFromTaker);
    }

    function testFuzz_conservation_tfap(uint32 feeBps, uint256 balA, uint256 balB, uint256 amount, bool exactIn, bool firstFromTaker) public {
        feeBps = uint32(bound(feeBps, 0, 1e9));
        balA = bound(balA, 1e12, 1e24); balB = bound(balB, 1e12, 1e24);
        amount = bound(amount, 1e6, exactIn ? balB : balA / 2);
        _runTFAP(feeBps, balA, balB, amount, exactIn, firstFromTaker);
    }
}
