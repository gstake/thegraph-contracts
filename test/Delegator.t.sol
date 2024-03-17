// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Delegator} from "../src/Delegator.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";


//forge test --fork-url  --fork-block-number  --match-test test_ -vvv
//forge test --match-test test_online_claimReward -vvv
contract TestDelegator is Test {
    Delegator public delegator;
    mapping(uint256 => address) addresses;

    function setUp() public {
        delegator = new Delegator();
    }

    function test_create1() public {
        console2.log("1");
        test_create(1);
    }

    function test_create11() public {
        console2.log("2");

        test_create(11);
    }

    function test_create21() public {
        console2.log("3");

        test_create(21);
    }

    function test_create(uint256 num) internal {
        for (uint256 i = 0; i < num; i++) {
            address instance=  Clones.clone(address(delegator));
            Delegator(instance).initialize();
            // console2.log("3");
            addresses[i] = instance;
        }
    }
}
