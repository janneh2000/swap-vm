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
import { Fee, FeeArgsBuilder } from "../../src/instructions/Fee.sol";

/// @notice FOURTH CAMPAIGN — PHASE 4/5 (full composition + ordering).
/// Exercise the REAL deployed Aqua AMM program shape `[aquaProtocolFee][concentrate][xycSwap]`
/// (the exact instruction set registered in AquaOpcodes for AquaSwapVMRouter) under EVERY
/// taker-controlled settlement lever, and assert the settlement is conservative and un-gameable:
///   (1) register (virtual Aqua balance) delta == real ERC20 delta for BOTH tokens (no drift);
///   (2) global token conservation across {taker, maker, feeTo};
///   (3) taker in/out registers equal the real ERC20 movements the taker sees;
///   (4) no round-trip profit (tin->tout->tin cannot leave the taker up on the start token).
/// Levers fuzzed: direction, exactIn/exactOut, isFirstTransferFromTaker, useTransferFromAndAquaPush,
/// fee bps, price bounds, reserves, amount. This is the composition the individual-instruction
/// campaigns never ran end-to-end on the deployed router in Aqua settlement mode.
contract AdvCanonicalFullTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    address feeTo;

    function setUp() public override { super.setUp(); feeTo = makeAddr("feeTo"); }

    function _td(address t, bool exactIn, bool firstFromTaker, bool useAquaPush) internal pure returns (bytes memory) {
        return TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: t, isExactIn: exactIn, shouldUnwrapWeth: false,
            hasPreTransferInCallback: true, hasPreTransferOutCallback: false,
            isStrictThresholdAmount: false, isFirstTransferFromTaker: firstFromTaker,
            useTransferFromAndAquaPush: useAquaPush,
            threshold: "", to: address(0), deadline: 0,
            preTransferInHookData: "", postTransferInHookData: "",
            preTransferOutHookData: "", postTransferOutHookData: "",
            preTransferInCallbackData: "", preTransferOutCallbackData: "",
            instructionsArgs: "", signature: ""
        }));
    }

    // canonical deployed program: aqua protocol fee (charged in tokenIn) -> concentrate -> xyc swap
    function _prog(uint32 bps, uint256 sMin, uint256 sMax) internal view returns (bytes memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        return bytes.concat(
            p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(bps, feeTo)),
            p.build(XYCConcentrate._xycConcentrateGrowLiquidity2D, XYCConcentrateArgsBuilder.build2D(sMin, sMax)),
            p.build(XYCSwap._xycSwapXD)
        );
    }

    struct Snap { uint256 tkIn; uint256 tkOut; uint256 mkIn; uint256 mkOut; uint256 fee; uint248 vIn; uint248 vOut; }

    function _snap(bytes32 h, MockTaker t, TokenMock tin, TokenMock tout) internal view returns (Snap memory s) {
        s.tkIn = tin.balanceOf(address(t));
        s.tkOut = tout.balanceOf(address(t));
        s.mkIn = tin.balanceOf(maker);
        s.mkOut = tout.balanceOf(maker);
        s.fee = tin.balanceOf(feeTo);
        (s.vIn,) = aqua.rawBalances(maker, address(swapVM), h, address(tin));
        (s.vOut,) = aqua.rawBalances(maker, address(swapVM), h, address(tout));
    }

    // one swap tin->tout, full conservation + register==real assertions
    function _doSwap(ISwapVM.Order memory o, bytes32 h, MockTaker t, TokenMock tin, TokenMock tout,
                     uint256 amt, bool exactIn, bool firstFromTaker, bool useAquaPush)
        internal returns (bool ok, uint256 ai, uint256 ao)
    {
        Snap memory a = _snap(h, t, tin, tout);
        try t.swap(o, address(tin), address(tout), amt, _td(address(t), exactIn, firstFromTaker, useAquaPush))
            returns (uint256 _ai, uint256 _ao)
        {
            ai = _ai; ao = _ao; ok = true;
            Snap memory b = _snap(h, t, tin, tout);

            // (3) taker registers == real ERC20 movement taker sees
            assertEq(a.tkIn - b.tkIn, ai, "taker tokenIn spent != amountIn");
            assertEq(b.tkOut - a.tkOut, ao, "taker tokenOut recv != amountOut");

            uint256 feeDelta = b.fee - a.fee;

            // (1) register==real for BOTH tokens
            assertEq(int256(b.mkIn) - int256(a.mkIn), int256(uint256(b.vIn)) - int256(uint256(a.vIn)), "tokenIn: real!=virtual");
            assertEq(int256(b.mkOut) - int256(a.mkOut), int256(uint256(b.vOut)) - int256(uint256(a.vOut)), "tokenOut: real!=virtual");

            // (2) global conservation: tokenIn = taker(-ai) + maker(+) + feeTo(+fee) == 0
            assertEq(-int256(ai) + (int256(b.mkIn) - int256(a.mkIn)) + int256(feeDelta), int256(0), "tokenIn not conserved");
            // tokenOut = taker(+ao) + maker(-) == 0  (no fee in tokenOut in this program)
            assertEq(int256(ao) + (int256(b.mkOut) - int256(a.mkOut)), int256(0), "tokenOut not conserved");

            // maker virtual tokenOut drop must equal what the taker received
            assertEq(uint256(a.vOut - b.vOut), ao, "maker virtual out drop != amountOut");
            // fee is a fraction of amountIn; maker gains (ai-fee) in tokenIn
            assertLe(feeDelta, ai, "fee exceeds amountIn");
            assertEq(uint256(b.vIn - a.vIn), ai - feeDelta, "maker virtual in gain != amountIn-fee");
        } catch { ok = false; }
    }

    function testFuzz_canonical_conservation(
        uint32 bps, uint256 balA, uint256 balB, uint256 sMin, uint256 sMax, uint256 amt,
        bool zeroForOne, bool exactIn, bool firstFromTaker, bool useAquaPush
    ) public {
        bps = uint32(bound(bps, 0, 5e8)); // 0..50%
        balA = bound(balA, 1e12, 1e24);
        balB = bound(balB, 1e12, 1e24);
        sMin = bound(sMin, 1e6, 1e17);
        sMax = bound(sMax, sMin + 1, 1e18);

        ISwapVM.Order memory o = createStrategy(_prog(bps, sMin, sMax));
        bytes32 h = shipStrategy(o, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);

        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenA.mint(address(t), 1e33); tokenB.mint(address(t), 1e33);

        (TokenMock tin, TokenMock tout) = zeroForOne ? (tokenA, tokenB) : (tokenB, tokenA);
        uint256 cap = zeroForOne ? balA : balB;
        _doSwap(o, h, t, tin, tout, bound(amt, 1e6, exactIn ? cap : cap / 2 + 1), exactIn, firstFromTaker, useAquaPush);
    }

    // No round-trip profit: buy tout with tin, then sell tout back for tin. Fee + curve must leave taker down.
    function testFuzz_canonical_no_roundtrip_profit(
        uint32 bps, uint256 balA, uint256 balB, uint256 sMin, uint256 sMax, uint256 amt, bool zeroForOne
    ) public {
        bps = uint32(bound(bps, 0, 1e7)); // 0..1% realistic
        balA = bound(balA, 1e15, 1e24);
        balB = bound(balB, 1e15, 1e24);
        sMin = bound(sMin, 1e6, 1e17);
        sMax = bound(sMax, sMin + 1, 1e18);

        ISwapVM.Order memory o = createStrategy(_prog(bps, sMin, sMax));
        bytes32 h = shipStrategy(o, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);

        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenA.mint(address(t), 1e33); tokenB.mint(address(t), 1e33);

        (TokenMock tin, TokenMock tout) = zeroForOne ? (tokenA, tokenB) : (tokenB, tokenA);
        uint256 start = tin.balanceOf(address(t));
        uint256 cap = zeroForOne ? balA : balB;

        (bool ok1,, uint256 got) = _doSwap(o, h, t, tin, tout, bound(amt, 1e9, cap / 4 + 1), true, false, false);
        if (!ok1 || got == 0) return;
        (bool ok2,,) = _doSwap(o, h, t, tout, tin, got, true, false, false);
        if (!ok2) return;

        assertLe(tin.balanceOf(address(t)), start, "CANONICAL round-trip PROFIT (taker gained start token)");
    }
}
