// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/WstGRT.sol";
import {WithdrawalNFT} from "../src/WithdrawalNFT.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @notice deploy cmd:
 *  forge script script/Update.s.sol:Update --rpc-url https://arbitrum-sepolia.blockpi.network/v1/rpc/public	 --broadcast   -vvvv
 */

contract Update is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("OWNER_PRI");
        vm.startBroadcast(deployerPrivateKey);

        update();

        vm.stopBroadcast();
    }

    function update() public {
        //https://forum.openzeppelin.com/t/foundry-upgradeable-contracts-error/38459/3
        Options memory opts;
        opts.unsafeSkipAllChecks = true;
        Upgrades.upgradeProxy(0x9253792d323Ef3E4BFd7481d8A010b054793B660, "WstGRT.sol", "", opts);
    }
}
