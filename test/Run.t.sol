// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Delegator} from "../src/Delegator.sol";
import "./BaseTest.t.sol";
import "../src/WstGRT.sol";
import "./interfaces/IEpochManager.sol";

import {WithdrawalNFT} from "../src/WithdrawalNFT.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

//forge test --fork-url https://sepolia-rollup.arbitrum.io/rpc  --fork-block-number 2700664   --match-test  test_call -vvv
contract TestGRun is Test, BaseTest {
    address owner = 0x1a7740a4B8e7c5750d1fD7b9AEB8349700a6714e;
    address GRT = 0xCA59cCeb39bE1808d7aA607153f4A5062daF3a83;
    address STAKING = 0x14e9B07Dc56A0B03ac8A58453B5cCCB289d6ec90;
    address gstake = 0x5a0712324a447A4Ba8c234960F7b97B60097aB64;
    address WithdrawQueueAddr = 0xdEc9272737C0F8CAD670ce30B026049bd13BEd0D;

    function setUp() public {}

    function test_run_call() public {
        vm.startPrank(owner);
        WstGRT.ActioinParam[] memory params = new WstGRT.ActioinParam[](2);
        params[0] = WstGRT.ActioinParam(2, 0x348f8242485456842595CdC0cAb5DF66E1D4d07c, 125429019780655651053);
        params[1] = WstGRT.ActioinParam(7, 0x348f8242485456842595CdC0cAb5DF66E1D4d07c, 244289156337264149691);
        // gstake.call{value: 0}(
        //     "0x2f177cbb0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000348f8242485456842595cdc0cab5df66e1d4d07c000000000000000000000000000000000000000000000006ccad64f0676c98ed0000000000000000000000000000000000000000000000000000000000000007000000000000000000000000348f8242485456842595cdc0cab5df66e1d4d07c00000000000000000000000000000000000000000000000d3e316d63aa7ec4bb"
        // );
        vm.stopPrank();
    }
}
