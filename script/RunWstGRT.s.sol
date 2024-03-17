// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/WstGRT.sol";
import {WithdrawalNFT} from "../src/WithdrawalNFT.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
/**
 * @notice deploy cmd:
 *  forge script script/RunWstGRT.s.sol:RunWstGRT --rpc-url https://arb-sepolia.g.alchemy.com/v2/ --broadcast --verify --etherscan-api-key   -vvvv
 */

contract RunWstGRT is Script {
    address owner = 0x1a7740a4B8e7c5750d1fD7b9AEB8349700a6714e;
    address GRT = 0xf8c05dCF59E8B28BFD5eed176C562bEbcfc7Ac04;
    address STAKING = 0x14e9B07Dc56A0B03ac8A58453B5cCCB289d6ec90;
    address gstake = 0x9253792d323Ef3E4BFd7481d8A010b054793B660;
    address WithdrawQueueAddr = 0x97ed4B05b9C1516Dca4F3CdBEc8D89A6E23d61Ea;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("OWNER_PRI");
        vm.startBroadcast(deployerPrivateKey);

        // WstGRT(gstake).setUndelegateInterval(7200);
        // WstGRT(gstake).setFeeRate(100000);
        // WstGRT(gstake).skipUndelegator(20);
        // undelegate();
        setPause(false);

        // deposit(1e21);
        // withdraw(1e19);
        // setUndelegateInterval(60);
        // callTest();
        // WstGRT(gstake).setOperator(owner);
        // WstGRT(gstake).setTreasury(0xb2dBf0410184a0E7D939991a7c46AA7e4d25d251);

        vm.stopBroadcast();
    }

    function setMaxPendingTime(uint40 timestamp_) public {
        WstGRT(gstake).setMaxRequestPendingTime(timestamp_);
        // setUndelegateInterval()
    }

    function setUndelegateInterval(uint40 timestamp_) public {
        WstGRT(gstake).setUndelegateInterval(timestamp_);
    }

    function deposit(uint256 amount) public {
        IWstGRTData.PermitInput memory resp = get_grt_permit();
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(WstGRT(gstake).permitGRT.selector, resp);
        data[1] = abi.encodeWithSelector(WstGRT(gstake).deposit.selector, amount, owner);
        WstGRT(gstake).multicall(data);
    }

    function undelegate() public {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 2;
        ids[1] = 3;
        ids[2] = 4;
        WstGRT(gstake).undelegate(ids);
    }

    function setPause(bool pause) public {
        if (pause) {
            WstGRT(gstake).pauseContract();
        } else {
            WstGRT(gstake).unpauseContract();
        }
    }

    function callTest() public {
        //    WstGRT.GStakeStorageView memory info =  WstGRT(gstake).getGstakeInfo();
        // console.log(info.theGraphStaking);
        // console.log(info.operator);
        // gstake.call{value: 0}("0x2f177cbb0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000348f8242485456842595cdc0cab5df66e1d4d07c000000000000000000000000000000000000000000000006ccad64f0676c98ed0000000000000000000000000000000000000000000000000000000000000007000000000000000000000000348f8242485456842595cdc0cab5df66e1d4d07c00000000000000000000000000000000000000000000000d3e316d63aa7ec4bb");
        // bool result = WstGRT(gstake).paused();
        WstGRT.GStakeStorageView memory info = WstGRT(gstake).getGstakeInfo();
        // uint256 result2 = WstGRT(gstake).totalAssets();
        // stakedGRT + $.pendingGRT - $.withdrawDebt
        console2.log("lockedGRT:", info.lockedGRT);
        console2.log("pendingGRT:", info.pendingGRT);
        console2.log("withdrawDebt:", info.withdrawDebt);
        console2.log("feeRate:", info.feeRate);
        uint256 result = WstGRT(gstake).getDelegationTaxPercentage();
        console2.log("result:", result);
        uint256 totalSupply = WstGRT(gstake).totalSupply();
        console2.log("totalSupply:", totalSupply);
        uint256 totalAssets = WstGRT(gstake).totalAssets();
        console2.log("totalAssets:", totalAssets);
        uint256 grtBalance = IERC20(GRT).balanceOf(gstake);
        console2.log("grtBalance:", grtBalance);

        // uint256 redeem = WstGRT(gstake).previewRedeem(1e21);
        uint256 redeem = 1e21 * totalAssets / totalSupply;
        console2.log("redeem:", redeem);

        // WstGRT(gstake).setGRT(GRT);
        // console2.log("result2:", result2);
        // WstGRT(gstake).unpauseContract();
        // WstGRT(gstake).withdraw(100, 0);
    }

    function withdraw(uint256 amount) public {
        WstGRT(gstake).withdraw(owner, amount);
    }

    function get_grt_domain_separator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
                ),
                keccak256("Graph Token"),
                keccak256("0"),
                block.chainid,
                GRT,
                0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa
            )
        );
    }

    function get_grt_permit() internal view returns (IWstGRTData.PermitInput memory) {
        uint256 deployerPrivateKey = vm.envUint("OWNER_PRI");
        return testPermitAndTransferFrom(
            deployerPrivateKey, GRT, owner, gstake, type(uint256).max, get_grt_domain_separator()
        );
    }

    function get_wstgrt_domain_separator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("wstGRT"),
                keccak256("1"),
                block.chainid,
                gstake
            )
        );
    }

    function get_wstgrt_permit() internal view returns (IWstGRTData.PermitInput memory) {
        uint256 deployerPrivateKey = vm.envUint("OWNER_PRI");
        return testPermitAndTransferFrom(
            deployerPrivateKey, gstake, owner, WithdrawQueueAddr, type(uint256).max, get_wstgrt_domain_separator()
        );
    }

    function testPermitAndTransferFrom(
        uint256 ownerPrivateKey,
        address _contract,
        address ownerAddress,
        address spenderAddress,
        uint256 value,
        bytes32 domainSeparator
    ) public view returns (IWstGRTData.PermitInput memory resp) {
        // vm.startPrank(spenderAddress, spenderAddress);

        IERC20Permit token = IERC20Permit(_contract);

        bytes32 _PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        uint256 nonce = token.nonces(ownerAddress);
        uint256 deadline = type(uint256).max;
        uint256 ownerPrivateKey_ = ownerPrivateKey;
        bytes32 structHash =
            keccak256(abi.encode(_PERMIT_TYPEHASH, ownerAddress, spenderAddress, value, nonce, deadline));

        // bytes32 DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();

        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey_, digest);

        resp = IWstGRTData.PermitInput(value, deadline, v, r, s);
        // vm.stopPrank();
    }
}
