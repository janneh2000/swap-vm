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

contract AdvPeggedMinTest is AquaSwapVMTest {
    using ProgramBuilder for Program;
    function setUp() public override { super.setUp(); }

    function _prog(uint256 x0, uint256 y0, uint256 A) internal view returns (bytes memory) {
        Program memory p = ProgramBuilder.init(_opcodes());
        return p.build(PeggedSwap._peggedSwapGrowPriceRange2D,
            PeggedSwapArgsBuilder.build(PeggedSwapArgsBuilder.Args({x0:x0,y0:y0,linearWidth:A,rateLt:1,rateGt:1})));
    }
    function _order(bytes memory prog, uint256 a, uint256 b) internal returns (ISwapVM.Order memory o, bytes32 h){
        o = createStrategy(prog); h = shipStrategy(o, tokenA, tokenB, a, b);
        tokenA.mint(maker, type(uint128).max); tokenB.mint(maker, type(uint128).max);
    }
    function _td(address t) internal pure returns (bytes memory){
        return TakerTraitsLib.build(TakerTraitsLib.Args({taker:t,isExactIn:true,shouldUnwrapWeth:false,hasPreTransferInCallback:true,hasPreTransferOutCallback:false,isStrictThresholdAmount:false,isFirstTransferFromTaker:false,useTransferFromAndAquaPush:false,threshold:"",to:address(0),deadline:0,preTransferInHookData:"",postTransferInHookData:"",preTransferOutHookData:"",postTransferOutHookData:"",preTransferInCallbackData:"",preTransferOutCallbackData:"",instructionsArgs:"",signature:""}));
    }
    function _leg(MockTaker t, ISwapVM.Order memory o, bool z, uint256 amt) internal returns(uint256 ai,uint256 ao,bool ok){
        (TokenMock tin,TokenMock tout)= z?(tokenA,tokenB):(tokenB,tokenA);
        try t.swap(o, address(tin), address(tout), amt, _td(address(t))) returns(uint256 i,uint256 oo){ai=i;ao=oo;ok=true;}catch{ok=false;}
    }

    // scan a single round-trip profit across scales at realistic A=100e27, x0=y0
    function test_scan_scales() public {
        uint256 A = 100e27;
        uint256[9] memory scales = [uint256(1e6),1e9,1e12,1e15,1e18,1e21,1e24,1e27,1e30];
        for (uint256 i=0;i<scales.length;i++){
            uint256 R = scales[i];
            (ISwapVM.Order memory o,) = _order(_prog(R,R,A), R, R);
            MockTaker t = new MockTaker(aqua, swapVM, address(this));
            tokenB.mint(address(t), type(uint128).max);
            uint256 amt = R/2;
            uint256 b0 = tokenB.balanceOf(address(t));
            (,uint256 gotA,bool ok1)=_leg(t,o,false,amt);
            if(!ok1||gotA==0){console.log("scale, leg1 fail", R);continue;}
            (,,bool ok2)=_leg(t,o,true,gotA);
            uint256 b1 = tokenB.balanceOf(address(t));
            if(!ok2){console.log("scale, leg2 fail", R);continue;}
            if (b1>b0) console.log("scale, PROFIT wei", R, b1-b0);
            else console.log("scale, loss wei", R, b0-b1);
        }
    }

    // amplification at realistic scale: 500 round-trips, does profit compound to material value?
    function test_amplify_realistic() public {
        uint256 R = 1e24;       // 1,000,000 tokens @ 18 dec
        uint256 A = 100e27;
        (ISwapVM.Order memory o,) = _order(_prog(R,R,A), R, R);
        MockTaker t = new MockTaker(aqua, swapVM, address(this));
        tokenB.mint(address(t), type(uint128).max);
        uint256 b0 = tokenB.balanceOf(address(t));
        uint256 amt = R/10;
        for (uint256 i=0;i<500;i++){
            (,uint256 gotA,bool ok1)=_leg(t,o,false,amt);
            if(!ok1||gotA==0) break;
            (,,bool ok2)=_leg(t,o,true,gotA);
            if(!ok2) break;
        }
        uint256 b1 = tokenB.balanceOf(address(t));
        if (b1>b0) console.log("amplify realistic PROFIT wei", b1-b0);
        else console.log("amplify realistic loss wei", b0-b1);
        // maker also may lose via reserve drift; log reserves handled elsewhere
    }
}
