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
import { Controls } from "../../src/instructions/Controls.sol";

/// @notice Malicious taker: during swap(A)'s preTransferInCallback, nests swap(B) on the SAME maker
/// (different orderHash, so the per-orderHash reentrancy lock does NOT block it). Checks whether the
/// nesting lets the attacker extract value or corrupt A's settlement (Specialist E — temporal/cross-order).
contract NestedTaker is ITakerCallbacks {
    Aqua public immutable AQUA;
    SwapVM public immutable SWAPVM;
    ISwapVM.Order orderA;
    ISwapVM.Order orderB;
    bytes32 hA;
    bytes32 hB;
    address tokenInAddr; // B (tokenIn for B->A swaps)
    address tokenOutAddr; // A
    bytes tdInner;
    bool entered;
    uint256 public innerAmount;

    constructor(Aqua a, SwapVM s) { AQUA = a; SWAPVM = s; }

    function config(ISwapVM.Order calldata a, ISwapVM.Order calldata b, bytes32 _hA, bytes32 _hB, address tin, address tout, bytes calldata inner, uint256 amt) external {
        orderA = a; orderB = b; hA = _hA; hB = _hB; tokenInAddr = tin; tokenOutAddr = tout; tdInner = inner; innerAmount = amt;
    }

    function runOuter(bytes calldata tdOuter, uint256 amt) external returns (uint256 ai, uint256 ao) {
        (ai, ao,) = SWAPVM.swap(orderA, tokenInAddr, tokenOutAddr, amt, tdOuter);
    }

    function preTransferInCallback(address maker, address, address tokenIn, address, uint256 amountIn, uint256, bytes32 orderHash, bytes calldata) external {
        if (orderHash == hA && !entered) {
            entered = true;
            // NEST: run swap B (same maker, different order). Not blocked by A's lock (different orderHash).
            SWAPVM.swap(orderB, tokenInAddr, tokenOutAddr, innerAmount, tdInner);
            // now settle A
            ERC20(tokenIn).approve(address(AQUA), amountIn);
            AQUA.push(maker, address(SWAPVM), orderHash, tokenIn, amountIn);
        } else {
            // B's callback (or re-entry): settle
            ERC20(tokenIn).approve(address(AQUA), amountIn);
            AQUA.push(maker, address(SWAPVM), orderHash, tokenIn, amountIn);
        }
    }
    function preTransferOutCallback(address, address, address, address, uint256, uint256, bytes32, bytes calldata) external {}
}

contract AdvNestedTest is AquaSwapVMTest {
    using ProgramBuilder for Program;

    function setUp() public override { super.setUp(); }

    function _xycOrder(uint64 salt, uint256 balA, uint256 balB) internal returns (ISwapVM.Order memory order, bytes32 h) {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory prog = bytes.concat(p.build(XYCSwap._xycSwapXD), p.build(Controls._salt, abi.encodePacked(salt)));
        order = createStrategy(prog);
        h = shipStrategy(order, tokenA, tokenB, balA, balB);
    }

    function _td(address t) internal pure returns (bytes memory) {
        return TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: t, isExactIn: true, shouldUnwrapWeth: false,
            hasPreTransferInCallback: true, hasPreTransferOutCallback: false,
            isStrictThresholdAmount: false, isFirstTransferFromTaker: false, useTransferFromAndAquaPush: false,
            threshold: "", to: address(0), deadline: 0,
            preTransferInHookData: "", postTransferInHookData: "", preTransferOutHookData: "", postTransferOutHookData: "",
            preTransferInCallbackData: "", preTransferOutCallbackData: "", instructionsArgs: "", signature: ""
        }));
    }

    function test_nested_cross_order_no_profit() public {
        // maker ships two XYC strategies, same pair, same reserves, different salt
        (ISwapVM.Order memory oA, bytes32 hA) = _xycOrder(1, 100e18, 100e18);
        (ISwapVM.Order memory oB, bytes32 hB) = _xycOrder(2, 100e18, 100e18);
        tokenA.mint(maker, 1e30); tokenB.mint(maker, 1e30);

        NestedTaker t = new NestedTaker(aqua, swapVM);
        uint256 outerAmt = 10e18;
        uint256 innerAmt = 10e18;
        // fund attacker with tokenB for both pushes (outer amountIn + inner amountIn)
        uint256 startB = 100e18;
        tokenB.mint(address(t), startB);
        t.config(oA, oB, hA, hB, address(tokenB), address(tokenA), _td(address(t)), innerAmt);

        uint256 beforeA = tokenA.balanceOf(address(t));
        uint256 beforeB = tokenB.balanceOf(address(t));
        t.runOuter(_td(address(t)), outerAmt);
        uint256 afterA = tokenA.balanceOf(address(t));
        uint256 afterB = tokenB.balanceOf(address(t));

        console.log("attacker A delta:", afterA - beforeA);       // received tokenA (out)
        console.log("attacker B spent:", beforeB - afterB);        // paid tokenB (in)
        // attacker paid (outerAmt + innerAmt) B, received sum of two amountOut A.
        // fair value: at 1:1 pool, each swap gives < amountIn. So total A out < total B in. No profit.
        // Assert attacker did not get more A than B paid (1:1 pool) => no value extraction.
        assertLe(afterA - beforeA, beforeB - afterB, "attacker extracted value via nested cross-order swaps");
    }
}
