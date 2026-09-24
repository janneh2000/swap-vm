// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { SwapVM } from "../../src/SwapVM.sol";
import { AquaSwapVMRouter } from "../../src/routers/AquaSwapVMRouter.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { MockTaker } from "../mocks/MockTaker.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { XYCSwap } from "../../src/instructions/XYCSwap.sol";

/// @notice FIFTH CAMPAIGN — Phase 1/2/12 (deployment topology, router/core mismatch, version drift).
/// The deployed AquaSwapVMRouter (AquaOpcodes) and the standard SwapVMRouter (base Opcodes) assign
/// DIFFERENT instructions to the SAME opcode number — e.g. opcode 18 is Balances._staticBalancesXD on
/// the base table but XYCSwap._xycSwapXD on the Aqua table; opcode 33 is TWAPSwap vs Extruction. So the
/// identical program bytes execute different logic depending on which router runs them. The only way to
/// weaponize that divergence is to get an order authorized for router A to EXECUTE on router B.
///
/// This test proves the Aqua-mode binding closes that door: Aqua balances are keyed by the executing
/// router (`app == address(this)`), so an order whose liquidity was shipped under router A produces
/// EMPTY balances on router B and cannot execute there. (Signature-mode orders are bound the analogous
/// way, through the EIP-712 domain's verifyingContract.) The opcode-table divergence is therefore a
/// maker/SDK configuration hazard, not an unprivileged cross-router attack.
contract AdvIntegrationRouterTest is AquaSwapVMTest {
    using ProgramBuilder for Program;

    function _td(address t) internal pure returns (bytes memory) {
        return TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: t, isExactIn: true, shouldUnwrapWeth: false,
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

    function test_cross_router_execution_fails_safe() public {
        // ship the strategy under the primary router (swapVM)
        Program memory p = ProgramBuilder.init(_opcodes());
        ISwapVM.Order memory o = createStrategy(p.build(XYCSwap._xycSwapXD));
        bytes32 h = shipStrategy(o, tokenA, tokenB, 1_000_000e18, 1_000_000e18);
        tokenA.mint(maker, 1e33); tokenB.mint(maker, 1e33);

        // a normal swap on the correct router works
        MockTaker t1 = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t1), 1e33);
        (, uint256 ao1) = t1.swap(o, address(tokenB), address(tokenA), 1000e18, _td(address(t1)));
        assertGt(ao1, 0, "baseline swap on correct router failed");

        // deploy a SECOND, independent AquaSwapVMRouter; the maker never shipped under it
        AquaSwapVMRouter router2 = new AquaSwapVMRouter(address(aqua), address(0), address(this), "SwapVM2", "1.0.0");
        // (the Aqua-mode orderHash is router-independent, so `o` is a valid order object for router2 too)
        assertEq(swapVM.hash(o), router2.hash(o), "aqua orderHash should be router-independent");

        // but router2's safeBalances(maker, router2, hash) are EMPTY -> the swap cannot execute there
        MockTaker t2 = new MockTaker(aqua, SwapVM(payable(address(router2))), address(this));
        tokenB.mint(address(t2), 1e33);
        vm.expectRevert(); // empty reserves on router2 => zero output (amountOut==0) / pull underflow => revert
        t2.swap(o, address(tokenB), address(tokenA), 1000e18, _td(address(t2)));

        // and the maker's real balances shipped under router1 are untouched by the router2 attempt
        (uint248 vA,) = aqua.rawBalances(maker, address(swapVM), h, address(tokenA));
        assertGt(uint256(vA), 0, "router1 balances must remain intact");
    }
}
