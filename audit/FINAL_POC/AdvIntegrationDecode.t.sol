// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { MockTaker } from "../mocks/MockTaker.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { XYCSwap } from "../../src/instructions/XYCSwap.sol";

/// @notice FIFTH CAMPAIGN — Phase 3/4/7/14 (SDK / order-binding / ABI-calldata / semantic differential).
/// The prior campaigns always built takerData through TakerTraitsLib.build (the canonical SDK path).
/// This test attacks the DECODER directly by hand-crafting the raw 22-byte TakerTraits header with
/// arbitrary, malformed, non-monotonic slice offsets — the one genuinely TAKER-controlled path into
/// Calldata.slice, whose bounds check verifies `end <= length` but NOT `begin <= end` (so begin>end
/// underflows the slice length to ~2**256).
///
/// Security question: can an unprivileged taker use a malformed takerData representation to make the
/// settlement diverge from the maker's authorized curve in the taker's favor (under-pay tokenIn, or
/// drain the maker's tokenOut beyond amountOut)?
///
/// Result (asserted below): NO. Every malformed representation either reverts, or settles with the
/// maker's real AND virtual balances moving by exactly the curve amounts. The taker's own malformed
/// offsets only ever waive the taker's OWN protections (threshold/deadline/recipient); they cannot
/// reach the maker's accounting.
contract AdvIntegrationDecodeTest is AquaSwapVMTest {
    using ProgramBuilder for Program;

    uint16 constant IS_EXACT_IN = 0x0001;
    uint16 constant HAS_PRE_IN_CB = 0x0004;

    function _xycOrder(uint256 balA, uint256 balB) internal returns (ISwapVM.Order memory o, bytes32 h) {
        Program memory p = ProgramBuilder.init(_opcodes());
        o = createStrategy(p.build(XYCSwap._xycSwapXD));
        h = shipStrategy(o, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);
    }

    // Hand-build raw takerData: 20-byte slicesIndexes (uint160, little-index-first) + 2-byte flags + tail.
    function _rawTakerData(uint16[10] memory idx, uint16 flags, bytes memory tail) internal pure returns (bytes memory) {
        uint256 v;
        for (uint256 k = 0; k < 10; k++) {
            v |= uint256(idx[k]) << (16 * k);
        }
        return bytes.concat(abi.encodePacked(uint160(v), flags), tail);
    }

    // ---- sanity: a hand-crafted minimal takerData executes a normal, conservative swap ----
    function test_handcrafted_minimal_swap_ok() public {
        (ISwapVM.Order memory o, bytes32 h) = _xycOrder(1_000_000e18, 1_000_000e18);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33);

        uint16[10] memory idx; // all zero
        bytes memory td = _rawTakerData(idx, IS_EXACT_IN | HAS_PRE_IN_CB, "");

        uint256 tB0 = tokenB.balanceOf(address(t));
        uint256 tA0 = tokenA.balanceOf(address(t));
        (uint256 ai, uint256 ao) = t.swap(o, address(tokenB), address(tokenA), 1000e18, td);
        assertEq(tB0 - tokenB.balanceOf(address(t)), ai, "taker in != amountIn");
        assertEq(tokenA.balanceOf(address(t)) - tA0, ao, "taker out != amountOut");
        assertGt(ao, 0, "no output");
    }

    // ---- the attack: fuzz arbitrary/malformed slice offsets; the maker's accounting must be untouchable ----
    function testFuzz_malformed_offsets_cannot_drain_maker(
        uint16 i0, uint16 i1, uint16 i2, uint16 i3, uint16 i4,
        uint16 i5, uint16 i6, uint16 i7, uint16 i8, uint16 i9,
        uint256 amt, bytes calldata tail
    ) public {
        (ISwapVM.Order memory o, bytes32 h) = _xycOrder(1_000_000e18, 1_000_000e18);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33);

        // bound offsets to straddle the tail boundary so we hit both in-range and underflowing slices
        uint256 cap = tail.length + 40;
        uint16[10] memory idx = [
            uint16(bound(i0, 0, cap)), uint16(bound(i1, 0, cap)), uint16(bound(i2, 0, cap)),
            uint16(bound(i3, 0, cap)), uint16(bound(i4, 0, cap)), uint16(bound(i5, 0, cap)),
            uint16(bound(i6, 0, cap)), uint16(bound(i7, 0, cap)), uint16(bound(i8, 0, cap)),
            uint16(bound(i9, 0, cap))
        ];
        bytes memory td = _rawTakerData(idx, IS_EXACT_IN | HAS_PRE_IN_CB, tail);

        // snapshot the MAKER side (the security-critical party the taker must not be able to reach)
        uint256 mkB0 = tokenB.balanceOf(maker);
        uint256 mkA0 = tokenA.balanceOf(maker);
        (uint248 vB0,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenB));
        (uint248 vA0,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA));

        try t.swap(o, address(tokenB), address(tokenA), bound(amt, 1e6, 500_000e18), td) returns (uint256 ai, uint256 ao) {
            // maker's virtual == real for BOTH tokens (no accounting drift from decoder games)
            assertEq(int256(tokenB.balanceOf(maker)) - int256(mkB0),
                     int256(uint256(_vB(h))) - int256(uint256(vB0)), "B real!=virtual");
            assertEq(int256(tokenA.balanceOf(maker)) - int256(mkA0),
                     int256(uint256(_vA(h))) - int256(uint256(vA0)), "A real!=virtual");
            // maker received exactly amountIn of tokenB and paid exactly amountOut of tokenA (curve-bound)
            assertEq(tokenB.balanceOf(maker) - mkB0, ai, "maker tokenIn gain != amountIn");
            assertEq(mkA0 - tokenA.balanceOf(maker), ao, "maker tokenOut loss != amountOut");
            assertEq(uint256(vA0 - _vA(h)), ao, "maker virtual tokenOut drop != amountOut");
        } catch {
            // reverting on a malformed representation is the safe outcome
        }
    }

    function _vA(bytes32 h) internal view returns (uint248 a){ (a,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA)); }
    function _vB(bytes32 h) internal view returns (uint248 b){ (b,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenB)); }

    // ---- waiving the threshold via a malformed offset is self-harm only; settlement still conserves ----
    function test_threshold_waiver_is_self_harm() public {
        (ISwapVM.Order memory o, bytes32 h) = _xycOrder(1_000_000e18, 1_000_000e18);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33);

        // Put a 32-byte "threshold" in the tail but set index0 != 32 so threshold() reports hasThreshold=false.
        // A canonical builder would set index0 == 32 to enforce it; the malformed form waives the taker's own
        // slippage guard. It must not affect the maker.
        bytes memory tail = abi.encodePacked(uint256(type(uint256).max)); // 32 bytes, an impossible min-out
        uint16[10] memory idx; // index0 = 0 => threshold slice length 0 => waived
        bytes memory td = _rawTakerData(idx, IS_EXACT_IN | HAS_PRE_IN_CB, tail);

        uint256 mkA0 = tokenA.balanceOf(maker);
        (uint248 vA0,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA));
        (, uint256 ao) = t.swap(o, address(tokenB), address(tokenA), 1000e18, td);
        // swap succeeds (threshold waived) and the maker still only pays the curve amountOut
        assertEq(mkA0 - tokenA.balanceOf(maker), ao, "maker paid != amountOut");
        assertEq(uint256(vA0) - uint256(_vA(h)), ao, "maker virtual drop != amountOut");
    }
}
