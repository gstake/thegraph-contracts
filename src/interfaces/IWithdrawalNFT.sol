// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IWithdrawalNFT {
    function mint(address to) external returns (uint256 _tokenId);
    function burn(uint256 _tokenId) external;
}
