// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./interfaces/IWithdrawalNFT.sol";

/// @notice During the user withdraw process, an NFT will be created and associated with the user's withdraw request. Only the address that holds the NFT will have the ability to claim the withdrawn GRT.
contract WithdrawalNFT is IWithdrawalNFT, ERC721Enumerable {
    error InvalidWstGRT(address sender);

    address public WstGRT;
    uint256 public tokenId;

    modifier onlyWstGRT() {
        if (msg.sender != WstGRT) revert InvalidWstGRT(msg.sender);
        _;
    }

    constructor() ERC721("WithdrawQueue", "WQ") {}

    function mint(address to) external override onlyWstGRT returns (uint256 _tokenId) {
        _tokenId = ++tokenId;
        _safeMint(to, _tokenId);
    }

    function burn(uint256 _tokenId) external override onlyWstGRT {
        _update(address(0), _tokenId, _msgSender());
    }

    /// @dev It can only be initialized once and remains unalterable thereafter.
    function setWstGRT(address _WstGRT) external {
        require(WstGRT == address(0), "initialized");
        WstGRT = _WstGRT;
    }

    /// @dev Only the WstGRT contract possesses the necessary authorizations, rendering the need for explicit authorization unnecessary.
    function _isAuthorized(address owner, address spender, uint256 tokenId_) internal view override returns (bool) {
        return spender == WstGRT || super._isAuthorized(owner, spender, tokenId_);
    }
}
