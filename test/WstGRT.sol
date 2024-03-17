// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Delegator} from "../src/Delegator.sol";
import "./BaseTest.t.sol";
import "../src/WstGRT.sol";
import "./interfaces/IEpochManager.sol";

import {WithdrawalNFT} from "../src/WithdrawalNFT.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

//forge test --fork-url https://goerli-rollup.arbitrum.io/rpc  --fork-block-number  --match-test test_ -vvv
//forge test --match-test test_online_claimReward -vvv
//https://github.com/graphprotocol/indexer/blob/main/docs/networks/arbitrum-goerli.md
contract TestWstGRT is Test, BaseTest {
    Delegator public delegator;
    WstGRT public wstGRT;
    WithdrawalNFT public wq;
    address owner = 0x1a7740a4B8e7c5750d1fD7b9AEB8349700a6714e;
    uint256 ownerPrivateKey; //0x1a7740a4B8e7c5750d1fD7b9AEB8349700a6714e's private key in .env file
    address GRT = 0xCA59cCeb39bE1808d7aA607153f4A5062daF3a83;
    address STAKING = 0x14e9B07Dc56A0B03ac8A58453B5cCCB289d6ec90;
    address epochManager = 0x3C39036a76104D7c6D3eF13a21477C0fE23A3Aa2;
    uint256 public testNum = 0;

    mapping(uint256 => address) addresses;

    function setUp() public {
        delegator = new Delegator();
        wstGRT = new WstGRT();
        wq = new WithdrawalNFT();
        wstGRT.initialize(GRT, address(wq), STAKING, owner, owner, owner);
        wq.setWstGRT(address(wstGRT));
        vm.startPrank(owner);
        wstGRT.setOperator(owner);
        vm.stopPrank();
        ownerPrivateKey = vm.envUint("OWNER_PRI");

        vm.label(address(wstGRT), "WstGRT");
        vm.label(GRT, "GRT");
        vm.label(STAKING, "STAKING");
        vm.label(owner, "OWNER");
        vm.label(address(wq), "WithdrawQueue");
        // vm.label(address(wstGRT), "WstGRT");
    }

    function test_deposit() public {
        _deposit(2e20, true);
        _deposit(2e20, false);
    }

    function _deposit(uint256 amount, bool permit) public {
        if (!permit) {
            vm.startPrank(owner);
            wstGRT.deposit(amount, owner);
            vm.stopPrank();
            return;
        }
        IWstGRTData.PermitInput memory _permit = get_grt_permit();
        // bytes[] memory data = new bytes[](2);
        // data[0] = abi.encodeWithSelector(wstGRT.permitGRT.selector, resp);
        // data[1] = abi.encodeWithSelector(wstGRT.deposit.selector, amount, owner);
        vm.startPrank(owner);
        wstGRT.permitGRT(_permit);
        // wstGRT.depositWithPermit(amount, owner, _permit);
        vm.stopPrank();
    }

    function test_withdraw() public {
        _deposit(2e20, true);
        _withdraw(1e20, true);
        vm.startPrank(owner);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        wstGRT.claimWithdrawals(ids);
        vm.stopPrank();
    }

    function _withdraw(uint256 num, bool permit) public {
        if (!permit) {
            vm.startPrank(owner);
            wstGRT.withdraw(owner, num);
            vm.stopPrank();
        }
        vm.startPrank(owner);
        wstGRT.withdraw(owner, num);
        vm.stopPrank();
    }

    function test_delegate() public {
        _deposit(4e20, true);

        wstGRT.createDelegator(10);

        //delegate
        WstGRT.ActioinParam[] memory actions = new WstGRT.ActioinParam[](4);
        actions[0] = WstGRT.ActioinParam(0, 0x56577167dCDD1A3de2e58d53fc2BE0B622D82A7C, 1e20);
        actions[1] = WstGRT.ActioinParam(0, 0x98c641cE2297BF04DF03313cF699AA20aAebC907, 1e20);
        actions[2] = WstGRT.ActioinParam(1, 0x56577167dCDD1A3de2e58d53fc2BE0B622D82A7C, 1e20);
        actions[3] = WstGRT.ActioinParam(1, 0x98c641cE2297BF04DF03313cF699AA20aAebC907, 1e20);
        vm.startPrank(owner);
        wstGRT.delegate(actions);
        vm.stopPrank();
        WstGRT.GStakeStorageView memory data = wstGRT.getGstakeInfo();
        assertEq(data.pendingGRT, 0);
    }

    function test_wq_undelegate() public {
        _deposit(4e20, true);

        wstGRT.createDelegator(10);

        //delegate
        WstGRT.ActioinParam[] memory actions = new WstGRT.ActioinParam[](4);
        actions[0] = WstGRT.ActioinParam(0, 0x56577167dCDD1A3de2e58d53fc2BE0B622D82A7C, 1e20);
        actions[1] = WstGRT.ActioinParam(0, 0x98c641cE2297BF04DF03313cF699AA20aAebC907, 1e20);
        actions[2] = WstGRT.ActioinParam(1, 0x56577167dCDD1A3de2e58d53fc2BE0B622D82A7C, 1e20);
        actions[3] = WstGRT.ActioinParam(1, 0x98c641cE2297BF04DF03313cF699AA20aAebC907, 1e20);
        vm.startPrank(owner);
        wstGRT.delegate(actions);
        vm.stopPrank();
        //withdraw
        _withdraw(wstGRT.balanceOf(owner), true);

        vm.warp(block.timestamp + 86400);

        //wq undelegate
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        address[] memory delegators = wstGRT.getDelegators();

        actions[0].amount = _get_delegator_share(0x56577167dCDD1A3de2e58d53fc2BE0B622D82A7C, delegators[0]);
        actions[1].amount = _get_delegator_share(0x98c641cE2297BF04DF03313cF699AA20aAebC907, delegators[0]);
        actions[2].amount = _get_delegator_share(0x56577167dCDD1A3de2e58d53fc2BE0B622D82A7C, delegators[1]);
        actions[3].amount = _get_delegator_share(0x98c641cE2297BF04DF03313cF699AA20aAebC907, delegators[1]);

        vm.startPrank(owner);
        wstGRT.undelegate(ids);
        vm.stopPrank();

        vm.roll(block.timestamp + 186400);
        vm.warp(block.timestamp + 186400);
        IEpochManager(epochManager).runEpoch();

        // IEpochManager(epochManager).runEpoch();

        vm.startPrank(owner);
        IERC20(GRT).transfer(address(wstGRT), 4);
        vm.stopPrank();

        wstGRT.claimUndelegation(1);
        vm.startPrank(owner);
        wstGRT.claimWithdrawals(ids);
        vm.stopPrank();
    }

    function _get_delegator_share(address indexer, address _delegator) public view returns (uint256) {
        IGraphStaking.Delegation memory _delegation = IGraphStaking(STAKING).getDelegation(indexer, _delegator);
        return _delegation.shares;
    }

    function test_create1() public {
        console2.log("1");
        test_create(1);
    }

    function test_num1() public {
        for (uint256 i = 0; i < 10; i++) {
            testNum = i;
        }
    }

    function test_num2() public {
        for (uint256 i = 0; i < 110; i++) {
            testNum = i;
        }
    }

    function test_num3() public {
        for (uint256 i = 0; i < 20; i++) {
            testNum = i;
        }
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
            address instance = Clones.clone(address(delegator));
            Delegator(instance).initialize();
            // console2.log("3");
            addresses[i] = instance;
        }
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
                0xe33842a7acd1d5a1d28f25a931703e5605152dc48d64dc4716efdae1f5659591
            )
        );
    }

    function get_grt_permit() internal returns (IWstGRTData.PermitInput memory) {
        return testPermitAndTransferFrom(
            ownerPrivateKey, GRT, owner, address(wstGRT), type(uint256).max, get_grt_domain_separator()
        );
    }

    function test_keccak256() public pure {
        bytes32 bytes32wstGRT =
            keccak256(abi.encode(uint256(keccak256("wstGRT.storage.WstGRT")) - 1)) & ~bytes32(uint256(0xff));
        console2.logBytes32(bytes32wstGRT);
    }
}
