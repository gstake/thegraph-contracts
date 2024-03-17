pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/Delegator.sol";
import "../src/WstGRT.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

abstract contract BaseTest is Test {
    function testPermitAndTransferFrom(
        uint256 ownerPrivateKey,
        address _contract,
        address ownerAddress,
        address spenderAddress,
        uint256 value,
        bytes32 domainSeparator
    ) public returns (IWstGRTData.PermitInput memory resp) {
        vm.startPrank(spenderAddress, spenderAddress);

        IERC20Permit token = IERC20Permit(_contract);

        bytes32 _PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        //需要获得这个签名计数器里的计数
        uint256 nonce = token.nonces(ownerAddress);
        uint256 deadline = type(uint256).max;
        uint256 ownerPrivateKey_ = ownerPrivateKey;
        bytes32 structHash =
            keccak256(abi.encode(_PERMIT_TYPEHASH, ownerAddress, spenderAddress, value, nonce, deadline));

        // bytes32 DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();

        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey_, digest);

        resp = IWstGRTData.PermitInput(value, deadline, v, r, s);
        vm.stopPrank();
    }
}
