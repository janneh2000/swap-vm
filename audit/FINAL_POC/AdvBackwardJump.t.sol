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
import { Controls, ControlsArgsBuilder } from "../../src/instructions/Controls.sol";

/// @notice FOURTH CAMPAIGN — PHASE 5 (instruction ordering / re-entry into the interpreter).
/// The VM's runLoop dispatches on a program counter that any control instruction can move
/// backward (Controls._jump sets an absolute PC). If a maker (or a manipulated program) could
/// re-run a value-computing instruction after amountIn/amountOut are already set, the second run
/// could pull tokenIn / push tokenOut a SECOND time against the same computed amounts — a double
/// settlement / drain. This test proves the recompute guards
/// (`require(amountIn == 0 || amountOut == 0)`) on every value-computing instruction defeat that:
/// a backward jump onto an already-executed curve/fee/concentrate REVERTS rather than double-settling.
/// Note the program is bound to the strategy hash, so a taker cannot craft this; it is a
/// defense-in-depth check on the interpreter itself.
contract AdvBackwardJumpTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    address feeTo;

    function setUp() public override { super.setUp(); feeTo = makeAddr("feeTo"); }

    function _td() internal view returns (bytes memory) {
        return TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: address(taker), isExactIn: true, shouldUnwrapWeth: false,
            hasPreTransferInCallback: true, hasPreTransferOutCallback: false,
            isStrictThresholdAmount: false, isFirstTransferFromTaker: false,
            useTransferFromAndAquaPush: false,
            threshold: "", to: address(0), deadline: 0,
            preTransferInHookData: "", postTransferInHookData: "",
            preTransferOutHookData: "", postTransferOutHookData: "",
            preTransferInCallbackData: "", preTransferOutCallbackData: "",
            instructionsArgs: "", signature: ""
        }));
    }

    function _run(bytes memory prog, uint256 amt) internal returns (bool ok) {
        ISwapVM.Order memory o = createStrategy(prog);
        bytes32 h = shipStrategy(o, tokenB, tokenA, 1_000_000e18, 1_000_000e18);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);
        tokenB.mint(address(taker), 1e33);
        // measure maker real balances to detect any double-settlement if it somehow did not revert
        uint256 mkA0 = tokenA.balanceOf(maker);
        (uint248 vA0,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA));
        try taker.swap(o, address(tokenB), address(tokenA), amt, _td()) returns (uint256, uint256 ao) {
            ok = true;
            // If execution succeeded, it MUST be a single, conservative settlement — the maker's
            // real tokenOut drop equals the virtual drop equals amountOut (no double push).
            uint256 mkA1 = tokenA.balanceOf(maker);
            (uint248 vA1,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA));
            assertEq(mkA0 - mkA1, ao, "maker real out drop != amountOut (double settle?)");
            assertEq(uint256(vA0 - vA1), ao, "maker virtual out drop != amountOut (double settle?)");
        } catch { ok = false; }
    }

    // [xycSwap][jump->0]  : jump back onto xycSwap after amounts computed -> RecomputeDetected revert
    function test_backjump_xyc_reverts() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory xyc = p.build(XYCSwap._xycSwapXD);
        // xyc occupies bytes [0 .. len(xyc)-1]; jump target 0 re-enters xyc
        bytes memory jmp = p.build(Controls._jump, ControlsArgsBuilder.buildJump(0));
        bool ok = _run(bytes.concat(xyc, jmp), 1000e18);
        assertFalse(ok, "backward jump re-ran XYCSwap without reverting (double-compute!)");
    }

    // [aquaFee][xyc][jump->0] : jump back onto the fee instruction -> fee recompute guard revert
    function test_backjump_fee_reverts() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory fee = p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(1e6, feeTo));
        bytes memory xyc = p.build(XYCSwap._xycSwapXD);
        bytes memory jmp = p.build(Controls._jump, ControlsArgsBuilder.buildJump(0));
        bool ok = _run(bytes.concat(fee, xyc, jmp), 1000e18);
        assertFalse(ok, "backward jump re-ran Fee+XYC without reverting (double-settle!)");
    }

    // [concentrate][xyc][jump->0] : jump back onto concentrate after amounts set -> concentrate guard revert
    function test_backjump_concentrate_reverts() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory conc = p.build(XYCConcentrate._xycConcentrateGrowLiquidity2D, XYCConcentrateArgsBuilder.build2D(5e17, 2e18));
        bytes memory xyc = p.build(XYCSwap._xycSwapXD);
        bytes memory jmp = p.build(Controls._jump, ControlsArgsBuilder.buildJump(0));
        bool ok = _run(bytes.concat(conc, xyc, jmp), 1000e18);
        assertFalse(ok, "backward jump re-ran Concentrate+XYC without reverting");
    }

    // control: same program WITHOUT the back-jump settles once, conservatively (proves the harness is sound)
    function test_forward_baseline_settles_once() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory conc = p.build(XYCConcentrate._xycConcentrateGrowLiquidity2D, XYCConcentrateArgsBuilder.build2D(5e17, 2e18));
        bytes memory xyc = p.build(XYCSwap._xycSwapXD);
        bool ok = _run(bytes.concat(conc, xyc), 1000e18);
        assertTrue(ok, "baseline canonical swap should succeed");
    }
}
