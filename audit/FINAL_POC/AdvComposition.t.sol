// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
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
import { PeggedSwap, PeggedSwapArgsBuilder } from "../../src/instructions/PeggedSwap.sol";
import { Fee, FeeArgsBuilder } from "../../src/instructions/Fee.sol";
import { Controls } from "../../src/instructions/Controls.sol";
import { dynamic } from "../utils/Dynamic.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Second-campaign adversarial composition harness.
/// Focus: round-trip (A->B->A) profit = value extracted from maker; real-settlement conservation;
/// and compositions NOT covered by test/invariants/* (esp. PeggedSwap+Decay / PeggedSwap+Concentrate).
contract AdvCompositionTest is AquaSwapVMTest {
    using ProgramBuilder for Program;

    function setUp() public override {
        super.setUp();
    }

    // Build order from raw program bytes, ship with virtual reserves, fund maker wallet generously.
    function _deploy(bytes memory program, uint256 balA, uint256 balB) internal returns (ISwapVM.Order memory order, bytes32 h) {
        order = createStrategy(program);
        h = shipStrategy(order, tokenA, tokenB, balA, balB);
        // fund maker wallet far beyond virtual reserves so pulls never fail for real-balance reasons
        tokenA.mint(maker, 1e30);
        tokenB.mint(maker, 1e30);
    }

    // One exact-in swap leg using an existing taker with pre-owned tokenIn. Returns (amountIn, amountOut).
    function _leg(MockTaker t, ISwapVM.Order memory order, bool zeroForOne, uint256 amountIn) internal returns (uint256, uint256) {
        (address tin, address tout) = zeroForOne ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));
        bytes memory td = TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: address(t), isExactIn: true, shouldUnwrapWeth: false,
            hasPreTransferInCallback: true, hasPreTransferOutCallback: false,
            isStrictThresholdAmount: false, isFirstTransferFromTaker: false, useTransferFromAndAquaPush: false,
            threshold: "", to: address(0), deadline: 0,
            preTransferInHookData: "", postTransferInHookData: "", preTransferOutHookData: "", postTransferOutHookData: "",
            preTransferInCallbackData: "", preTransferOutCallbackData: "", instructionsArgs: "", signature: ""
        }));
        return t.swap(order, tin, tout, amountIn, td);
    }

    // ---- program builders (raw, via ProgramBuilder + AquaOpcodesDebug _opcodes()) ----
    function _pXYC() internal view returns (bytes memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        return p.build(XYCSwap._xycSwapXD);
    }
    function _pDecayXYC(uint16 period) internal view returns (bytes memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        return bytes.concat(p.build(Decay._decayXD, DecayArgsBuilder.build(period)), p.build(XYCSwap._xycSwapXD));
    }
    function _pPegged(uint256 x0, uint256 y0, uint256 A) internal view returns (bytes memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        return p.build(PeggedSwap._peggedSwapGrowPriceRange2D,
            PeggedSwapArgsBuilder.build(PeggedSwapArgsBuilder.Args({x0: x0, y0: y0, linearWidth: A, rateLt: 1, rateGt: 1})));
    }
    function _pDecayPegged(uint16 period, uint256 x0, uint256 y0, uint256 A) internal view returns (bytes memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        return bytes.concat(
            p.build(Decay._decayXD, DecayArgsBuilder.build(period)),
            p.build(PeggedSwap._peggedSwapGrowPriceRange2D,
                PeggedSwapArgsBuilder.build(PeggedSwapArgsBuilder.Args({x0: x0, y0: y0, linearWidth: A, rateLt: 1, rateGt: 1})))
        );
    }

    // ============ sanity: plain XYC round-trip must not profit the taker ============
    function test_sanity_XYC_roundtrip_no_profit() public {
        (ISwapVM.Order memory order,) = _deploy(_pXYC(), 100e18, 100e18);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        uint256 startB = 10e18;
        tokenB.mint(address(t), startB);
        (, uint256 gotA) = _leg(t, order, false, startB);   // B->A
        (, uint256 gotB) = _leg(t, order, true, gotA);      // A->B
        console.log("XYC roundtrip startB, gotB:", startB, gotB);
        assertLe(gotB, startB, "XYC roundtrip profited taker (theft)");
    }

    // ============ TARGET: PeggedSwap + Decay round-trip (composition NOT invariant-tested) ============
    function test_pegged_decay_roundtrip_no_profit() public {
        // pegged stable pool, x0=y0=100e18, A=100e27 (tight peg), decay 300s
        (ISwapVM.Order memory order,) = _deploy(_pDecayPegged(300, 100e18, 100e18, 100e27), 100e18, 100e18);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        uint256 startB = 5e18;
        tokenB.mint(address(t), startB);
        (, uint256 gotA) = _leg(t, order, false, startB);   // B->A
        // warp past decay so the second leg is not penalized
        vm.warp(block.timestamp + 301);
        (, uint256 gotB) = _leg(t, order, true, gotA);      // A->B
        console.log("PeggedDecay roundtrip startB, gotB:", startB, gotB);
        assertLe(gotB, startB, "PeggedDecay roundtrip profited taker (theft)");
    }

    // ============ TARGET: plain PeggedSwap round-trip (baseline for the above) ============
    function test_pegged_roundtrip_no_profit() public {
        (ISwapVM.Order memory order,) = _deploy(_pPegged(100e18, 100e18, 100e27), 100e18, 100e18);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        uint256 startB = 5e18;
        tokenB.mint(address(t), startB);
        (, uint256 gotA) = _leg(t, order, false, startB);
        (, uint256 gotB) = _leg(t, order, true, gotA);
        console.log("Pegged roundtrip startB, gotB:", startB, gotB);
        assertLe(gotB, startB, "Pegged roundtrip profited taker (theft)");
    }
}
