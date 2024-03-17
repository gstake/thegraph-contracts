// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @notice This contract serves solely as a proxy user, as the undelegation process in The Graph entails a freeze period. undelegate repeatedly with the same delegator would trigger a refresh of the freeze period. Therefore, to ensure smooth undelegation in each period, we create multiple delegators for delegation, guaranteeing that undelegation requests are sequentially routed through different delegators.
contract Delegator {
    address public owner;

    /// @dev The owner is immutable and cannot be modified.
    function initialize() public {
        require(owner == address(0), "initialized");
        owner = msg.sender;
    }

    /// @dev Only the owner is authorized to invoke this action.
    /// @param target Target address
    /// @param data data
    /// @param value eth amount
    function execute(address target, bytes calldata data, uint256 value) public returns (bytes memory) {
        require(msg.sender == owner, "not owner");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return Address.verifyCallResult(success, returndata);
    }
}
