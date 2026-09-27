// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { MockTaker } from "../mocks/MockTaker.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { PeggedSwap, PeggedSwapArgsBuilder } from "../../src/instructions/PeggedSwap.sol";
import { PeggedSwapMath } from "../../src/libs/PeggedSwapMath.sol";

/// @notice Directly attack the fixes for OZ v1 Critical-1 (solve() precision loss) and Critical-3 (axis
/// mismatch) by measuring the PeggedSwap invariant C in a FIXED (lt/gt) frame before/after each real Aqua
/// swap. The Criticals manifested as C DECREASING (maker pays out more than the curve dictates). The fix
/// must keep C non-decreasing (rounding favors maker) for ALL params, incl. near-zero A (unstable region),
/// asymmetric anchors, reverse direction, and rate/decimal asymmetry.
contract AdvPeggedInvariantTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    function setUp() public override { super.setUp(); }

    function _lt() internal view returns (TokenMock ltT, TokenMock gtT) {
        return address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    // C in the fixed lt/gt frame from current Aqua balances
    function _C(bytes32 h, uint256 cx0, uint256 cy0, uint256 A, uint256 rLt, uint256 rGt) internal view returns (uint256) {
        (TokenMock ltT, TokenMock gtT) = _lt();
        (uint248 balLt,) = aqua.rawBalances(maker, address(swapVM), h, address(ltT));
        (uint248 balGt,) = aqua.rawBalances(maker, address(swapVM), h, address(gtT));
        return PeggedSwapMath.invariantFromReserves(uint256(balLt) * rLt, uint256(balGt) * rGt, cx0, cy0, A);
    }

    function _td(address t, bool exactIn) internal pure returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:t,isExactIn:exactIn,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:false,isStrictThresholdAmount:false,isFirstTransferFromTaker:false,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }

    // one swap; assert invariant C does not materially decrease
    function _swapAndCheckC(uint256 balLt0, uint256 balGt0, uint256 A, uint256 rLt, uint256 rGt, bool z, bool exactIn, uint256 amt) internal {
        (TokenMock ltT, TokenMock gtT) = _lt();
        uint256 cx0 = balLt0 * rLt;
        uint256 cy0 = balGt0 * rGt;
        // build pegged with these anchors (config.x0=lt anchor, config.y0=gt anchor)
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory prog = p.build(PeggedSwap._peggedSwapGrowPriceRange2D,
            PeggedSwapArgsBuilder.build(PeggedSwapArgsBuilder.Args({x0:cx0, y0:cy0, linearWidth:A, rateLt:rLt, rateGt:rGt})));
        ISwapVM.Order memory order = createStrategy(prog);
        // ship lt->balLt0, gt->balGt0
        bytes32 h = shipStrategy(order, ltT, gtT, balLt0, balGt0);
        ltT.mint(maker, type(uint128).max); gtT.mint(maker, type(uint128).max);

        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        (TokenMock tin, TokenMock tout) = z ? (ltT, gtT) : (gtT, ltT);
        tin.mint(address(t), type(uint128).max);

        uint256 cBefore = _C(h, cx0, cy0, A, rLt, rGt);
        try t.swap(order, address(tin), address(tout), amt, _td(address(t), exactIn)) returns (uint256, uint256) {
            uint256 cAfter = _C(h, cx0, cy0, A, rLt, rGt);
            // C must not decrease beyond a wei-level normalized tolerance (rounding favors maker => C grows)
            // tolerance: 1e9 in ONE(1e27)-scaled invariant units == 1e-18 relative. Any real decrease dwarfs this.
            if (cAfter + 1e9 < cBefore) {
                console.log("C DECREASED (maker loss). before, after:", cBefore, cAfter);
                console.log("A, amt:", A, amt);
                console.log("balLt0, balGt0:", balLt0, balGt0);
            }
            assertGe(cAfter + 1e9, cBefore, "PeggedSwap invariant C decreased => maker loss (Critical re-emerged)");
        } catch { /* revert is acceptable (balance sufficiency / no-solution) */ }
    }

    // sanity fixed case
    function test_C_preserved_balanced() public {
        _swapAndCheckC(1000e18, 1000e18, 100e27, 1, 1, false, true, 50e18);
    }

    // FUZZ: near-zero A (the unstable region Critical-1 was about), symmetric
    function testFuzz_C_smallA(uint256 A, uint256 amt, bool z, bool exactIn) public {
        A = bound(A, 0, 1e24); // near-zero .. small (guidance "volatile A~0-0.2" => tiny in 1e27 scale)
        uint256 R = 1000e18;
        _swapAndCheckC(R, R, A, 1, 1, z, exactIn, bound(amt, 1, R/2));
    }

    // FUZZ: asymmetric anchors + reverse direction (Critical-3 axis-mismatch scenario)
    function testFuzz_C_asymmetric(uint256 balLt, uint256 balGt, uint256 A, uint256 amt, bool z, bool exactIn) public {
        balLt = bound(balLt, 1e6, 1e24);
        balGt = bound(balGt, 1e6, 1e24);
        A = bound(A, 0, 5000e27);
        uint256 amtCap = z ? balLt : balGt;
        _swapAndCheckC(balLt, balGt, A, 1, 1, z, exactIn, bound(amt, 1, amtCap/2 + 1));
    }

    // FUZZ: rate/decimal asymmetry (different decimals) + reverse direction
    function testFuzz_C_rates(uint256 balLt, uint256 balGt, uint256 A, uint256 amt, bool z, bool exactIn, bool r) public {
        balLt = bound(balLt, 1e6, 1e18);
        balGt = bound(balGt, 1e6, 1e18);
        A = bound(A, 0, 5000e27);
        uint256 rLt = r ? 1 : 1e12;
        uint256 rGt = r ? 1e12 : 1;
        uint256 amtCap = z ? balLt : balGt;
        _swapAndCheckC(balLt, balGt, A, rLt, rGt, z, exactIn, bound(amt, 1, amtCap/2 + 1));
    }
}
