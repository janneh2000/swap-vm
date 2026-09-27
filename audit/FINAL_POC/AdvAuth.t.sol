// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { MockTaker } from "../mocks/MockTaker.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { XYCSwap } from "../../src/instructions/XYCSwap.sol";
import { Fee, FeeArgsBuilder } from "../../src/instructions/Fee.sol";
import { Controls } from "../../src/instructions/Controls.sol";

/// @notice Authorization-binding: the Aqua orderHash = keccak256(abi.encode(order)) binds the WHOLE order
/// (incl. program/fees). A taker cannot execute a tampered program, foreign tokens, or tokenIn==tokenOut.
contract AdvAuthTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    address feeTo;
    function setUp() public override { super.setUp(); feeTo=makeAddr("feeTo"); }

    function _td(address t) internal pure returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:t,isExactIn:true,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:false,isStrictThresholdAmount:false,isFirstTransferFromTaker:false,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }

    // maker ships an order WITH a 10% protocol fee; taker tries to run the SAME reserves but a program
    // with the fee stripped (cheaper for taker). orderHash differs -> safeBalances finds nothing -> revert.
    function test_cannot_strip_fee_instruction() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory withFee = bytes.concat(
            p.build(Fee._aquaProtocolFeeAmountInXD, FeeArgsBuilder.buildProtocolFee(1e8, feeTo)),
            p.build(XYCSwap._xycSwapXD)
        );
        ISwapVM.Order memory shipped = createStrategy(withFee);
        shipStrategy(shipped, tokenA, tokenB, 100e18, 100e18);
        tokenA.mint(maker, 1e30); tokenB.mint(maker, 1e30);

        // attacker-built order: same maker/traits but program WITHOUT the fee
        bytes memory noFee = p.build(XYCSwap._xycSwapXD);
        ISwapVM.Order memory tampered = createStrategy(noFee);

        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 50e18);
        vm.expectRevert(); // safeBalances: token not in active strategy for tampered orderHash
        t.swap(tampered, address(tokenB), address(tokenA), 50e18, _td(address(t)));
    }

    // taker cannot swap a token pair the maker never shipped
    function test_cannot_use_foreign_token() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        ISwapVM.Order memory order = createStrategy(p.build(XYCSwap._xycSwapXD));
        shipStrategy(order, tokenA, tokenB, 100e18, 100e18);
        tokenA.mint(maker, 1e30); tokenB.mint(maker, 1e30);
        TokenMock tokenC = new TokenMock("C","C");
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenC.mint(address(t), 50e18);
        vm.expectRevert();
        t.swap(order, address(tokenC), address(tokenA), 50e18, _td(address(t)));
    }

    // tokenIn == tokenOut is rejected by MakerTraits.validate before any transfer
    function test_cannot_same_token() public {
        Program memory p = ProgramBuilder.init(_opcodes());
        ISwapVM.Order memory order = createStrategy(p.build(XYCSwap._xycSwapXD));
        shipStrategy(order, tokenA, tokenB, 100e18, 100e18);
        tokenA.mint(maker, 1e30); tokenB.mint(maker, 1e30);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenA.mint(address(t), 50e18);
        vm.expectRevert();
        t.swap(order, address(tokenA), address(tokenA), 50e18, _td(address(t)));
    }
}
