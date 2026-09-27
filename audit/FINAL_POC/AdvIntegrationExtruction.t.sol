// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { MockTaker } from "../mocks/MockTaker.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { Extruction, IExtruction, IStaticExtruction } from "../../src/instructions/Extruction.sol";
import { SwapQuery, SwapRegisters } from "../../src/libs/VM.sol";

/// A maker-chosen Extruction target that tries to abuse its register-replacement power:
/// it returns whatever (amountIn, amountOut) it is configured with, ignoring any real curve.
contract EvilExtruction is IExtruction, IStaticExtruction {
    uint256 public forcedIn;
    uint256 public forcedOut;
    function set(uint256 i, uint256 o) external { forcedIn = i; forcedOut = o; }
    function extruction(bool, uint256 nextPC, SwapQuery calldata, SwapRegisters calldata s, bytes calldata, bytes calldata)
        external view override(IExtruction, IStaticExtruction) returns (uint256, uint256, SwapRegisters memory)
    {
        SwapRegisters memory u = s;
        u.amountIn = forcedIn;
        u.amountOut = forcedOut;
        return (nextPC, 0, u);
    }
}

/// @notice FIFTH CAMPAIGN — Phase 9/13 (callback/integration boundary + integration business logic).
/// Extruction is the deployed escape hatch that lets a maker's chosen external target REPLACE the whole
/// SwapRegisters (amountIn/amountOut/balances). It is the single most powerful integration primitive.
/// It requires a MALICIOUS MAKER (the target is a hash-bound program arg), so it is out of the
/// unprivileged-attacker model — but we prove the in-scope settlement still bounds it:
///   (1) an inflated amountOut cannot conjure funds — Aqua.pull is bounded by the maker's own balance,
///       so an over-large amountOut reverts (underflow) rather than draining a third party;
///   (2) whatever amounts survive, the maker's real == virtual balance movement holds (conservation);
///   (3) the taker's threshold still governs the taker's exposure.
/// i.e. "malicious maker via Extruction" ≠ "unprivileged drain of another party".
contract AdvIntegrationExtructionTest is AquaSwapVMTest {
    using ProgramBuilder for Program;

    function _td(address t, bool exactIn) internal pure returns (bytes memory) {
        return TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: t, isExactIn: exactIn, shouldUnwrapWeth: false,
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

    function _extructionOrder(address target, uint256 balA, uint256 balB) internal returns (ISwapVM.Order memory o, bytes32 h) {
        Program memory p = ProgramBuilder.init(_opcodes());
        // program args = target(20) + no extra extruction args
        o = createStrategy(p.build(Extruction._extruction, abi.encodePacked(target)));
        h = shipStrategy(o, tokenA, tokenB, balA, balB);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);
    }

    // (1) inflated amountOut beyond the maker's balance MUST revert, not drain
    function test_extruction_cannot_conjure_funds() public {
        uint256 makerOut = 10_000e18; // maker only has this much tokenA in the strategy
        EvilExtruction evil = new EvilExtruction();
        evil.set(1e18 /*amountIn*/, 1_000_000e18 /*amountOut >> maker balance*/);
        (ISwapVM.Order memory o,) = _extructionOrder(address(evil), 10_000e18, makerOut);

        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33);

        vm.expectRevert(); // Aqua.pull underflows: cannot pay out more tokenOut than the maker holds
        t.swap(o, address(tokenB), address(tokenA), 1e18, _td(address(t), true));
    }

    // (2) a within-balance forced settlement still conserves and touches ONLY this maker
    function test_extruction_within_balance_conserves() public {
        EvilExtruction evil = new EvilExtruction();
        evil.set(500e18 /*amountIn*/, 700e18 /*amountOut*/);
        (ISwapVM.Order memory o, bytes32 h) = _extructionOrder(address(evil), 1_000_000e18, 1_000_000e18);

        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33);

        uint256 mkB0 = tokenB.balanceOf(maker);
        uint256 mkA0 = tokenA.balanceOf(maker);
        (uint248 vB0,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenB));
        (uint248 vA0,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA));
        uint256 tB0 = tokenB.balanceOf(address(t));
        uint256 tA0 = tokenA.balanceOf(address(t));

        // exactIn binds takerAmount == amountIn, so the taker must declare exactly the target's forcedIn
        // (a target that forces a *different* amountIn is rejected by TakerTraits.validate — proven separately).
        (uint256 ai, uint256 ao) = t.swap(o, address(tokenB), address(tokenA), 500e18, _td(address(t), true));
        assertEq(ai, 500e18, "amountIn not forced value");
        assertEq(ao, 700e18, "amountOut not forced value");

        // taker paid exactly ai, received exactly ao
        assertEq(tB0 - tokenB.balanceOf(address(t)), ai, "taker in != ai");
        assertEq(tokenA.balanceOf(address(t)) - tA0, ao, "taker out != ao");
        // maker real == virtual, both tokens
        assertEq(tokenB.balanceOf(maker) - mkB0, ai, "maker B real gain != ai");
        assertEq(mkA0 - tokenA.balanceOf(maker), ao, "maker A real loss != ao");
        assertEq(uint256(_vB(h)) - uint256(vB0), ai, "maker B virtual gain != ai");
        assertEq(uint256(vA0) - uint256(_vA(h)), ao, "maker A virtual loss != ao");
    }

    // (3) taker amount-binding: a target that forces an amountIn different from the taker's declared
    //     exactIn amount is rejected by TakerTraits.validate — the taker cannot be made to overpay.
    function test_extruction_cannot_force_taker_overpay() public {
        EvilExtruction evil = new EvilExtruction();
        evil.set(500e18 /*forced amountIn*/, 700e18);
        (ISwapVM.Order memory o,) = _extructionOrder(address(evil), 1_000_000e18, 1_000_000e18);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), 1e33);
        // taker declares only 1e18 exactIn; target tries to force 500e18 in => must revert
        vm.expectRevert();
        t.swap(o, address(tokenB), address(tokenA), 1e18, _td(address(t), true));
    }

    function _vA(bytes32 h) internal view returns (uint248 a){ (a,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA)); }
    function _vB(bytes32 h) internal view returns (uint248 b){ (b,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenB)); }
}
