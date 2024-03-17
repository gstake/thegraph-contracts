// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/WstGRT.sol";
import {WithdrawalNFT} from "../src/WithdrawalNFT.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @notice deploy cmd:
 *  forge script script/DeployWstGRT.s.sol:DeployWstGRT --rpc-url https://arbitrum-sepolia.blockpi.network/v1/rpc/public --broadcast    -vvvv --ffi
 *  forge script script/DeployWstGRT.s.sol:DeployWstGRT --rpc-url https://eth-sepolia.public.blastapi.io --broadcast    -vvvv
 */

contract DeployWstGRT is Script {
    WstGRT public gStake;
    WithdrawalNFT public wq;
    address owner = 0x1a7740a4B8e7c5750d1fD7b9AEB8349700a6714e;
    address treasury = 0xb2dBf0410184a0E7D939991a7c46AA7e4d25d251;
    address GRT = 0xf8c05dCF59E8B28BFD5eed176C562bEbcfc7Ac04;
    address STAKING = 0x865365C425f3A593Ffe698D9c4E6707D14d51e08;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("OWNER_PRI");
        vm.startBroadcast(deployerPrivateKey);
        depoloyWstGRT();
        vm.stopBroadcast();
    }

    function depoloyWstGRT() public {
        wq = new WithdrawalNFT();
        address _gstake = Upgrades.deployTransparentProxy(
            "WstGRT.sol", owner, abi.encodeCall(WstGRT.initialize, (GRT, address(wq), STAKING, owner, owner, treasury))
        );
        gStake = WstGRT(_gstake);
        gStake.setMaxRequestPendingTime(3600);
        wq.setWstGRT(address(gStake));
    }
}
