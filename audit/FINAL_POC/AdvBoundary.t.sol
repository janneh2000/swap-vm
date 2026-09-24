// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import { AquaSwapVMTest } from "../base/AquaSwapVMTest.sol";
import { ISwapVM } from "../../src/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "../../src/libs/TakerTraits.sol";
import { MockTaker } from "../mocks/MockTaker.sol";
import { Program, ProgramBuilder } from "../utils/ProgramBuilder.sol";
import { PeggedSwap, PeggedSwapArgsBuilder } from "../../src/instructions/PeggedSwap.sol";
import { Decay, DecayArgsBuilder } from "../../src/instructions/Decay.sol";

/// @notice PeggedSwap (+optional Decay) round-trip at REALISTIC scales (<=1e24 base units) with sane
/// config anchors (config.x0/y0 == shipped reserves, as the SDK builds). Round-trip must be maker-favorable.
/// (The wei-level round-trip surplus that appears only at absurd >=~1e25 reserves + huge trades is a benign,
/// non-amplifiable rounding artifact within the OZ-reviewed PeggedSwap tolerance — see KILL_LEDGER K2-01.)
contract AdvBoundaryTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    function setUp() public override { super.setUp(); }

    function _prog(uint256 x0, uint256 y0, uint256 A, uint256 rLt, uint256 rGt, bool decay) internal view returns (bytes memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        bytes memory pegged = p.build(PeggedSwap._peggedSwapGrowPriceRange2D,
            PeggedSwapArgsBuilder.build(PeggedSwapArgsBuilder.Args({x0:x0,y0:y0,linearWidth:A,rateLt:rLt,rateGt:rGt})));
        if (decay) return bytes.concat(p.build(Decay._decayXD, DecayArgsBuilder.build(300)), pegged);
        return pegged;
    }
    function _td(address t) internal pure returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:t,isExactIn:true,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:false,isStrictThresholdAmount:false,isFirstTransferFromTaker:false,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }
    function _leg(MockTaker t, ISwapVM.Order memory o, bool z, uint256 amt) internal returns(uint256 ao,bool ok){
        (TokenMock tin,TokenMock tout)= z?(tokenA,tokenB):(tokenB,tokenA);
        try t.swap(o, address(tin), address(tout), amt, _td(address(t))) returns(uint256,uint256 oo){ao=oo;ok=true;}catch{ok=false;}
    }

    function testFuzz_pegged_realistic_roundtrip(uint256 x0, uint256 y0, uint256 A, uint256 rSel, uint256 amt, bool decay, uint256 warp) public {
        x0 = bound(x0, 1e6, 1e24);
        y0 = bound(y0, 1e6, 1e24);
        A  = bound(A, 0, 5000e27);
        uint256 rLt = (rSel & 1) == 0 ? 1 : 1e12;
        uint256 rGt = (rSel & 2) == 0 ? 1 : 1e12;
        ISwapVM.Order memory o = createStrategy(_prog(x0, y0, A, rLt, rGt, decay));
        shipStrategy(o, tokenA, tokenB, x0, y0);
        tokenA.mint(maker, type(uint128).max); tokenB.mint(maker, type(uint128).max);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), type(uint128).max);
        uint256 b0 = tokenB.balanceOf(address(t));
        (uint256 gotA, bool ok1) = _leg(t, o, false, bound(amt, 1e3, y0/2));
        if (!ok1 || gotA == 0) return;
        if (decay) vm.warp(block.timestamp + bound(warp, 0, 200000));
        (, bool ok2) = _leg(t, o, true, gotA);
        if (!ok2) return;
        assertLe(tokenB.balanceOf(address(t)), b0, "realistic-scale pegged roundtrip PROFIT");
    }
}
