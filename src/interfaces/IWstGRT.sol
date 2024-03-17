// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IWstGRTData.sol";

interface IWstGRT is IWstGRTData {
    event NewDelegator(uint256 index, address delegator);
    event Delegate(uint256 amount, uint256 percentage);
    event IndexerDelegate(address indexer, address delegator, uint256 amount, uint256 share);
    event RewardUpdated(address delegator, address indexer, uint256 reward);
    event IndexerUnDelegate(uint256 undelegationId, address indexer, address delegator, uint256 amount, uint256 share);
    event ClaimUndelegation(uint256 undelegationId);
    event WithdrawalRequested(uint256 tokenId, address owner, uint256 wstGRT, uint256 grt, uint256 timestamp);
    event WRStatusChanged(uint256 id, WRStatus status);
    event WithdrawalClaimed(uint256 tokenId, address owner, uint256 timestamp, uint256 amount);
    event RequestUndelegate(uint40 undelegateId, uint256 totalGRT, uint256 lockedGRT, uint256 timestamp, uint256[] ids);
    event Withdraw(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event UndelegateLimit(uint256 amount);
    event Treasury(address treasury);
    event MaxRequestPendingTime(uint40 period);
    event UndelegateInterval(uint40 period);
    event FeeRate(uint256 feeRate);
    event Operator(address operator);
    event WQ(address withdrawQueue);

    error InvalidDelegator(address delegator);
    error InvalidParam();
    error InvalidAmount();
    error ZeroAmount();
    error Undelegated(address indexer, address delegator);
    error InvalidOperator(address operator);
    error InvalidUndelegateId();
    error NotNeedUndelegate();
    error RequestAmountTooSmall();
    error RequestTooMuch();
    error NotClaimable();
    error UndelegateError(uint256 tokenId);
    error HaveUndelegated();
    error IndexerError();
}
