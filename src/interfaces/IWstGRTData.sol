// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IWstGRTData {
    enum WRStatus {
        Processing,
        Undelegating,
        Claimable
    }

    enum UndelegateStatus {
        Processing,
        Undelegating,
        Finished
    }

    struct DelegatorInfo {
        address indexer;
        uint256 shares;
        uint256 lastGRTPerShare;
    }

    struct UndelegateInfo {
        uint256 amountOfGRT;
        uint256 lockedGRT;
        UndelegateStatus status;
        uint40 timestamp;
        uint256 delegatorIndex;
    }

    struct WithdrawalRequest {
        uint256 wstGRT; // total wstGRT
        uint256 amountOfGRT; //
        uint256 undelegateId;
        WRStatus status;
        uint40 timestamp;
    }

    struct PermitInput {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
}
