// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IGraphStaking.sol";
import "./interfaces/IWstGRT.sol";
import "./interfaces/IWIthdrawalNFT.sol";
import "./Delegator.sol";

/**
 * @title WstGRT contract
 * @dev This contract provides user with the ability to stake and withdraw GRT,
 * while also offer the capability for the operator to delegate GRT to The Graph and withdraw delegation.
 */
contract WstGRT is
    IWstGRT,
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    MulticallUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice precision base for share rate
    uint256 private constant E18_PRECISION_BASE = 1e18;
    /// @notice cannot be modified
    uint32 public constant MAX_PPM = 1000000;
    uint256 private constant MINIMUM_DELEGATION = 1e18;

    // keccak256(abi.encode(uint256(keccak256("gstake.storage.WstGRT")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GStakeStorageLocation = 0xdbc5c30dc394a8ba5607f82f278032ef43e05fe8f8844da7ebc936a021c9a200;

    function _getGStakeStorage() private pure returns (GStakeStorage storage $) {
        assembly {
            $.slot := GStakeStorageLocation
        }
    }

    /// @custom:storage-location erc7201:gstake.storage.WstGRT
    struct GStakeStorage {
        address GRT; // GRT token address
        uint256 stakedGRT; // total asset
        uint256 pendingGRT; // the amount to delegate
        uint256 withdrawDebt; // the amount to undelegate
        uint256 lockedGRT; // the amount remaining to be withdrawn by user
        address theGraphStaking; //the graph address
        address withdrawQueue; //withdrawQueue nft address
        address operator; //operator address
        address treasury; // fee receiver
        uint256 feeRate; // 100000=10%  MAX_PPM
        address delegatorImpl; //delegator impl address
        address[] delegators; // delegators array
        mapping(address => DelegatorInfo) delegatorInfo; //delegator info
        uint40 maxRequestPendingTime; // the minimum matching time for a withdraw request
        uint40 undelegationId; // undelegation id , total undelegation
        uint40 lastUndelegateNum; // the period num of the last undelegate
        uint40 nextUndelegatorIndex; //the delegator index of the next undelegate
        uint40 undelegateInterval; //The interval time for undelegate.
        mapping(uint256 => UndelegateInfo) undelegations; // undelegate info
        mapping(uint256 => WithdrawalRequest) withdrawRequests; //withdraw queue
        mapping(uint256 => address) undelegationIndexer; // undelegate indexer
    }

    modifier onlyOperator() {
        GStakeStorage storage $ = _getGStakeStorage();
        if (msg.sender != $.operator) revert InvalidOperator(msg.sender);
        _;
    }

    function initialize(
        address GRT_,
        address wq_,
        address theGraphStaking_,
        address owner_,
        address operator_,
        address treasury_
    ) public initializer {
        __Ownable_init(owner_);
        __ERC20_init("wstGRT", "wstGRT");
        __ERC20Permit_init("wstGRT");
        GStakeStorage storage $ = _getGStakeStorage();
        $.GRT = GRT_;
        $.withdrawQueue = wq_;
        $.delegatorImpl = address(new Delegator());
        $.theGraphStaking = theGraphStaking_;
        $.operator = operator_;
        $.treasury = treasury_;
        $.maxRequestPendingTime = 12 hours;
        $.feeRate = 100000;
        $.undelegateInterval = 1 days;
    }

    /**
     * @notice Authorize first, then deposit
     * @param assets Amount of GRT
     * @param receiver Receiver of wstGRT
     * @param _permit Approve information of GRT
     */
    function depositWithPermit(uint256 assets, address receiver, IWstGRTData.PermitInput calldata _permit) external {
        permitGRT(_permit);
        _deposit(_msgSender(), assets, receiver);
    }

    /**
     * @notice Deposit
     * @param assets Amount of GRT
     * @param receiver Receiver of wstGRT
     */
    function deposit(uint256 assets, address receiver) external {
        _deposit(_msgSender(), assets, receiver);
    }

    function permitGRT(IWstGRTData.PermitInput calldata _permit) public {
        IERC20Permit(asset()).permit(
            msg.sender, address(this), _permit.value, _permit.deadline, _permit.v, _permit.r, _permit.s
        );
    }

    /**
     * @notice Burns the user's wstGRT and grants them an NFT.
     * @dev The amount of GRT the user is entitled to receive will be calculated based on the current ratio.
     * For security reasons, there are limits on the redemption amount. Please refer to the `undelegate` method for more details.
     * @param _owner Owner of wstGRT
     * @param amountOfWstGRT Amount of wstGRT
     * @return tokenId TokenId of the nft
     */
    function withdraw(address _owner, uint256 amountOfWstGRT) public returns (uint256 tokenId) {
        if (amountOfWstGRT == 0) revert ZeroAmount();
        uint256 amountOfGRT = _withdraw(_msgSender(), _owner, amountOfWstGRT);
        checkWithdrawalRequestAmount(amountOfGRT);
        tokenId = _enqueue(amountOfWstGRT, amountOfGRT, _owner);
        //match order
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        matchOrder(ids);
    }

    struct ActioinParam {
        uint256 delegatorIndex; // index of delegator
        address indexer; //indexer address
        uint256 amount; // GRT amount,which contains the graph delegation tax
    }

    /**
     * @notice Delegates GRT to the indexer of TheGraph through the delegator.
     * @dev Each delegator can only stake to one indexer. The specific quantity is calculated offline.
     */
    function delegate(ActioinParam[] calldata actions) external onlyOperator {
        updateRewardAllIndexer();
        GStakeStorage storage $ = _getGStakeStorage();
        address _theGraphStaking = $.theGraphStaking;
        uint256 size = actions.length;
        uint256 _index = 0;
        uint256 _totalGRT = 0;
        while (_index < size) {
            ActioinParam memory action = actions[_index];
            address delegator = $.delegators[action.delegatorIndex];
            DelegatorInfo storage delegatorInfo = $.delegatorInfo[delegator];
            address indexer = action.indexer;
            bool is_new;
            if (delegatorInfo.indexer != indexer) {
                delegatorInfo.indexer = indexer;
                is_new = true;
            }
            // Delegate tokens into the indexer
            uint256 _share = _delegate(_theGraphStaking, delegator, indexer, action.amount);
            if (is_new) {
                // init the delegator info, shares, lastGRTPerShare
                uint256 _GRTPerShare = getIndexerGRTPerShare(indexer);
                delegatorInfo.shares = _share;
                delegatorInfo.lastGRTPerShare = _GRTPerShare;
            } else {
                //update shares
                delegatorInfo.shares += _share;
            }
            emit IndexerDelegate(indexer, delegator, action.amount, _share);
            _totalGRT += action.amount;
            ++_index;
        }
        // Compute the actual delegation GRT, exclusive of delegation tax.
        uint32 _percentage = getDelegationTaxPercentage();
        _totalGRT = calcNetAmount(_percentage, _totalGRT);
        $.pendingGRT -= _totalGRT;
        $.stakedGRT += _totalGRT;
        emit Delegate(_totalGRT, _percentage);
    }

    /**
     * @notice Converts a portion of the matched amount into fees.
     * @dev Re-stakes GRT and converts it into wstGRT for distribution.
     */
    function collectFee() public {
        GStakeStorage storage $ = _getGStakeStorage();
        uint32 _percentage = getDelegationTaxPercentage();
        uint256 pendingGRT = calcGrossAmount(_percentage, $.pendingGRT);
        uint256 _bal = IERC20(asset()).balanceOf(address(this));
        if (_bal > pendingGRT + $.lockedGRT + 1e8) {
            uint256 _left = _bal - pendingGRT - $.lockedGRT;
            _deposit(address(this), _left, $.treasury);
        }
    }

    /**
     * @notice Updates the rewards for all delegators.
     * @dev The rewards are generated by the indexer closing the subgraph on The Graph.
     */
    function updateRewardAllIndexer() public {
        GStakeStorage storage $ = _getGStakeStorage();
        uint256 _size = $.delegators.length;
        address _theGraphStaking = $.theGraphStaking;
        uint256 currentIndex = 0;
        uint256 totalReward = 0;
        while (currentIndex < _size) {
            address delegator = $.delegators[currentIndex];
            totalReward += _updateReward($, _theGraphStaking, delegator);
            ++currentIndex;
        }
        _handleRewardFee($, totalReward);
    }

    /**
     * @notice Updates the rewards for specific delegators.
     * @param _delegatorIndexs The index of the delegators
     */
    function updateReward(uint256[] memory _delegatorIndexs) public {
        if (_delegatorIndexs.length == 0) revert InvalidParam();
        GStakeStorage storage $ = _getGStakeStorage();
        uint256 _size = _delegatorIndexs.length;
        address _theGraphStaking = $.theGraphStaking;
        uint256 currentIndex = 0;
        uint256 totalReward = 0;
        while (currentIndex < _size) {
            address delegator = $.delegators[_delegatorIndexs[currentIndex]];
            totalReward += _updateReward($, _theGraphStaking, delegator);
            ++currentIndex;
        }
        _handleRewardFee($, totalReward);
    }

    /**
     * @notice Redeems GRT from The Graph to fulfill user redemption requests.
     * @dev Only one delegator can be redeemed at a time within a certain period. During this period, the maximum redemption amount for a user is equal to the amount of GRT the delegator can redeem.  After the current redemption is processed, the limit will be updated for the next delegator.When a delegator redeems, the GRT will not be immediately distributed.
     * @param ids The NFT tokenIds of the withdraw requests.
     */
    function undelegate(uint256[] memory ids) external onlyOperator {
        GStakeStorage storage $ = _getGStakeStorage();
        uint256 delegatorIndex = $.nextUndelegatorIndex;

        // update delegation reward
        uint256[] memory _delegatorIndexs = new uint256[](1);
        _delegatorIndexs[0] = delegatorIndex;
        updateReward(_delegatorIndexs);

        // init a undelegate task
        uint256 undelegationId = _requestUndelegate(ids);

        // calc the delegate for this round.
        uint256 _lastUndelegateNum = block.timestamp / $.undelegateInterval;
        if (_lastUndelegateNum <= $.lastUndelegateNum) revert HaveUndelegated();
        $.lastUndelegateNum = uint40(_lastUndelegateNum);

        // undelegate from the graph.
        address delegator = $.delegators[delegatorIndex];
        address indexer = $.delegatorInfo[delegator].indexer;
        uint256 shares = $.undelegations[undelegationId].amountOfGRT * E18_PRECISION_BASE
            / $.delegatorInfo[delegator].lastGRTPerShare;
        uint256 amountOfGRT = _undelegate($.theGraphStaking, delegator, indexer, shares);
        emit IndexerUnDelegate(undelegationId, indexer, delegator, amountOfGRT, shares);

        // update the task
        $.delegatorInfo[delegator].shares -= shares;
        uint256 _need = $.undelegations[undelegationId].amountOfGRT;
        if (_need > amountOfGRT + 1e16 || amountOfGRT > _need + 1e16) revert InvalidAmount();
        $.undelegations[undelegationId].status = UndelegateStatus.Undelegating;
        $.undelegations[undelegationId].delegatorIndex = delegatorIndex;
        $.undelegationIndexer[undelegationId] = indexer;
        $.stakedGRT -= amountOfGRT;
        $.withdrawDebt -= _need;

        //update delegator index of next round
        uint256 nextIndex = $.nextUndelegatorIndex + 1;
        uint256 len = $.delegators.length;
        if (nextIndex < len && $.delegatorInfo[$.delegators[nextIndex]].indexer != address(0)) {
            $.nextUndelegatorIndex = uint40(nextIndex);
        } else {
            $.nextUndelegatorIndex = 0;
        }
    }

    /**
     * @notice  Specifies the delegator for the next undelegate task execution.
     * @param index The index of the next delegator.
     */

    function skipUndelegator(uint256 index) external onlyOperator {
        GStakeStorage storage $ = _getGStakeStorage();
        $.nextUndelegatorIndex = uint40(index);
    }

    /**
     * @notice  Claims redeemed GRT from The Graph.
     * @param undelegationId The id of the undelegation to be claimed.
     */
    function claimUndelegation(uint256 undelegationId) external {
        GStakeStorage storage $ = _getGStakeStorage();
        UndelegateInfo memory _delegationInfo = $.undelegations[undelegationId];
        if (_delegationInfo.status == UndelegateStatus.Finished) revert InvalidUndelegateId();
        $.undelegations[undelegationId].status = UndelegateStatus.Finished;
        uint256 delegatorIndex = _delegationInfo.delegatorIndex;
        address _theGraphStaking = $.theGraphStaking;
        address delegator = $.delegators[delegatorIndex];
        address indexer = $.undelegationIndexer[undelegationId];
        if (indexer == address(0)) {
            indexer = $.delegatorInfo[delegator].indexer;
        }
        // claim from the graph
        _withdrawDelegated(_theGraphStaking, delegator, indexer);
        $.lockedGRT += _delegationInfo.amountOfGRT;
        emit ClaimUndelegation(undelegationId);
    }

    /**
     * @notice Allows users to claim their redeemed GRT.
     * @param _tokenIds The NFT tokenIds of the withdraw requests.
     */
    function claimWithdrawals(uint256[] calldata _tokenIds) external {
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            claim(_tokenIds[i]);
        }
    }

    /**
     * @notice claim by user
     * @param tokenId The NFT tokenId of the withdraw request.
     */
    function claim(uint256 tokenId) public {
        GStakeStorage storage $ = _getGStakeStorage();
        address _owner = IERC721($.withdrawQueue).ownerOf(tokenId);
        WithdrawalRequest memory request = $.withdrawRequests[tokenId];
        bool normalClaimable = request.status == WRStatus.Claimable;
        bool specClaimable = request.status == WRStatus.Undelegating
            && $.undelegations[request.undelegateId].status == UndelegateStatus.Finished;
        if (!normalClaimable && !specClaimable) revert NotClaimable();
        uint256 amountOfGRT = request.amountOfGRT;
        _deleteRequest(tokenId);
        $.lockedGRT -= amountOfGRT;
        IERC20(asset()).safeTransfer(_owner, amountOfGRT);
        emit WithdrawalClaimed(tokenId, _owner, amountOfGRT, amountOfGRT);
    }

    /**
     * @notice Matches the pending redemption orders with new stakings.
     * @dev The wstGRT received by the staker is minted anew.
     * @param ids The NFT tokenIds of the withdraw requests.
     */
    function matchOrder(uint256[] memory ids) public {
        GStakeStorage storage $ = _getGStakeStorage();
        uint256 availGRT = $.pendingGRT;
        if (availGRT == 0) return;
        uint256 maxNum = ids.length;
        uint256 i = 0;
        uint256 totalGRT = 0;
        while (i < maxNum) {
            uint256 _tokenId = ids[i];
            WithdrawalRequest memory request = $.withdrawRequests[_tokenId];
            //match the order
            if (request.amountOfGRT + totalGRT <= availGRT && request.status == WRStatus.Processing) {
                totalGRT += request.amountOfGRT;
                $.withdrawRequests[_tokenId].status = WRStatus.Claimable;
                emit WRStatusChanged(_tokenId, WRStatus.Claimable);
            }
            if (totalGRT == availGRT) {
                break;
            }
            ++i;
        }
        if (totalGRT > 0) {
            $.pendingGRT -= totalGRT;
            $.withdrawDebt -= totalGRT;
            $.lockedGRT += totalGRT;
        }
        // collect the delegation tax
        collectFee();
    }

    /**
     * @notice create some delegator
     * @dev The number of delegators is primarily related to the redemption freeze period of The Graph.
     * @param num The number of delegators to be created.
     */
    function createDelegator(uint256 num) public onlyOperator {
        GStakeStorage storage $ = _getGStakeStorage();
        address _theGraphStaking = $.theGraphStaking;
        uint256 i = 0;
        while (i < num) {
            address instance = Clones.clone($.delegatorImpl);
            Delegator(instance).initialize();
            $.delegators.push(instance);
            bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, _theGraphStaking, type(uint256).max);
            address _GRT = asset();
            Delegator(instance).execute(_GRT, data, 0);
            ++i;
            uint256 index = $.delegators.length - 1;
            emit NewDelegator(index, instance);
        }
    }

    /// @notice set new withdrawQueue
    function setWQ(address _withdrawQueue) external onlyOwner {
        GStakeStorage storage $ = _getGStakeStorage();
        $.withdrawQueue = _withdrawQueue;
        emit WQ(_withdrawQueue);
    }

    /// @notice set new operator
    function setOperator(address _operator) external onlyOwner {
        GStakeStorage storage $ = _getGStakeStorage();
        $.operator = _operator;
        emit Operator(_operator);
    }

    /// @notice set fee rate
    function setFeeRate(uint256 feeRate_) external onlyOwner {
        GStakeStorage storage $ = _getGStakeStorage();
        if (feeRate_ > MAX_PPM) revert InvalidParam();
        $.feeRate = feeRate_;
        emit FeeRate(feeRate_);
    }

    /// @notice set new treasury
    function setTreasury(address _treasury) external onlyOwner {
        GStakeStorage storage $ = _getGStakeStorage();
        $.treasury = _treasury;
        emit Treasury(_treasury);
    }

    /// @notice set maxRequestPendingTime param
    function setMaxRequestPendingTime(uint40 period_) external onlyOwner {
        GStakeStorage storage $ = _getGStakeStorage();
        $.maxRequestPendingTime = period_;
        emit MaxRequestPendingTime(period_);
    }

    /// @notice set undelegateInterval param
    function setUndelegateInterval(uint40 period_) external onlyOwner {
        GStakeStorage storage $ = _getGStakeStorage();
        $.undelegateInterval = period_;
        emit UndelegateInterval(period_);
    }

    /// @notice pause contract
    function pauseContract() public onlyOwner {
        _pause();
    }

    /// @notice unpause contract
    function unpauseContract() public onlyOwner {
        _unpause();
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @notice get total assets
     * @return amount of total assets
     */
    function totalAssets() public view returns (uint256) {
        GStakeStorage storage $ = _getGStakeStorage();
        return $.stakedGRT + $.pendingGRT - $.withdrawDebt;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() internal pure returns (uint8) {
        return 0;
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function asset() public view returns (address) {
        GStakeStorage storage $ = _getGStakeStorage();
        return $.GRT;
    }

    function getDelegationTaxPercentage() public view returns (uint32) {
        GStakeStorage storage $ = _getGStakeStorage();
        address _theGraphStaking = $.theGraphStaking;
        return IGraphStaking(_theGraphStaking).delegationTaxPercentage();
    }
    /**
     * @dev  remove the graph deposit fee
     * @param  _delegationTaxPercentage config param of the graph staking
     */

    function calcNetAmount(uint32 _delegationTaxPercentage, uint256 amount) public pure returns (uint256) {
        return amount * (MAX_PPM - _delegationTaxPercentage) / MAX_PPM;
    }

    /**
     * @dev  add the graph deposit fee
     * @param  _delegationTaxPercentage config param of the graph staking
     */
    function calcGrossAmount(uint32 _delegationTaxPercentage, uint256 amount) public pure returns (uint256) {
        return amount * MAX_PPM / (MAX_PPM - _delegationTaxPercentage);
    }

    function getIndexerGRTPerShare(address indexer) public view returns (uint256) {
        GStakeStorage storage $ = _getGStakeStorage();
        address _theGraphStaking = $.theGraphStaking;
        IGraphStaking.DelegationPoolReturn memory _pool = IGraphStaking(_theGraphStaking).delegationPools(indexer);
        return _pool.tokens * E18_PRECISION_BASE / _pool.shares;
    }

    struct GStakeStorageView {
        uint256 stakedGRT;
        uint256 pendingGRT;
        uint256 withdrawDebt;
        uint256 lockedGRT;
        address theGraphStaking;
        address withdrawQueue;
        address operator;
        address treasury;
        uint256 feeRate;
        address delegatorImpl;
        uint40 maxRequestPendingTime;
        uint40 undelegationId;
        address GRT;
        uint256 lastUndelegateNum;
        uint256 nextUndelegatorIndex;
        uint40 undelegateInterval;
    }

    function getGstakeInfo() public view returns (GStakeStorageView memory) {
        GStakeStorage storage $ = _getGStakeStorage();
        return GStakeStorageView(
            $.stakedGRT,
            $.pendingGRT,
            $.withdrawDebt,
            $.lockedGRT,
            $.theGraphStaking,
            $.withdrawQueue,
            $.operator,
            $.treasury,
            $.feeRate,
            $.delegatorImpl,
            $.maxRequestPendingTime,
            $.undelegationId,
            $.GRT,
            $.lastUndelegateNum,
            $.nextUndelegatorIndex,
            $.undelegateInterval
        );
    }

    function getDelegators() public view returns (address[] memory) {
        GStakeStorage storage $ = _getGStakeStorage();
        address[] memory delegators = new address[]($.delegators.length);
        for (uint256 i = 0; i < delegators.length; i++) {
            delegators[i] = $.delegators[i];
        }
        return delegators;
    }

    function getDelegatorInfo(address _delegator) public view returns (DelegatorInfo memory) {
        GStakeStorage storage $ = _getGStakeStorage();
        return $.delegatorInfo[_delegator];
    }

    function getUndelegateInfo(uint256 _undelegationId) public view returns (UndelegateInfo memory) {
        GStakeStorage storage $ = _getGStakeStorage();
        return $.undelegations[_undelegationId];
    }

    function getWithdrawalRequest(uint256 _tokenId) public view returns (WithdrawalRequest memory) {
        GStakeStorage storage $ = _getGStakeStorage();
        return $.withdrawRequests[_tokenId];
    }

    /**
     * @dev Mint NFT and bind NFT information with redemption request
     * @param _theGraphStaking Address of the graph staking
     * @param delegator Address of delegator
     * @param indexer Address of indexer
     */
    function _withdrawDelegated(address _theGraphStaking, address delegator, address indexer)
        private
        returns (uint256 amountOfGRT)
    {
        bytes memory data = abi.encodeWithSelector(IGraphStaking.withdrawDelegated.selector, indexer, address(0));
        bytes memory returndata = Delegator(delegator).execute(_theGraphStaking, data, 0);
        amountOfGRT = abi.decode(returndata, (uint256));
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, address(this), amountOfGRT);
        Delegator(delegator).execute(asset(), transferData, 0);
    }

    /**
     * @dev Mint NFT and bind NFT information with redemption request
     * @param _amountOfWstGRT Amount of wstGRT
     * @param amountOfGRT Amount of the GRT
     * @param _owner Owner of wstGRT
     */
    function _enqueue(uint256 _amountOfWstGRT, uint256 amountOfGRT, address _owner) private returns (uint256 tokenId) {
        GStakeStorage storage $ = _getGStakeStorage();
        tokenId = IWithdrawalNFT($.withdrawQueue).mint(_owner);
        uint40 _timestamp = uint40(block.timestamp);
        $.withdrawRequests[tokenId] =
            WithdrawalRequest(_amountOfWstGRT, amountOfGRT, 0, WRStatus.Processing, _timestamp);
        emit WithdrawalRequested(tokenId, _owner, _amountOfWstGRT, amountOfGRT, _timestamp);
    }

    /**
     * @notice User stakes GRT
     * @param caller Address of the sender
     * @param assets Amount of the GRT
     * @param receiver Receiver of wstGRT
     */
    function _deposit(address caller, uint256 assets, address receiver) internal whenNotPaused {
        if (caller != address(this)) {
            SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        }
        uint32 _percentage = getDelegationTaxPercentage();
        uint256 shares = calcNetAmount(_percentage, previewDeposit(assets));
        assets = calcNetAmount(_percentage, assets);
        if (shares == 0 || assets == 0) revert InvalidAmount();
        _mint(receiver, shares);
        GStakeStorage storage $ = _getGStakeStorage();
        $.pendingGRT += assets;
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice User withdraw GRT
     * @param caller Address of the sender
     * @param owner Address of the wstGRT owner
     * @param shares Amount of wstGRT
     */
    function _withdraw(address caller, address owner, uint256 shares) internal whenNotPaused returns (uint256 assets) {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        GStakeStorage storage $ = _getGStakeStorage();
        assets = previewRedeem(shares);
        $.withdrawDebt += assets;
        _burn(owner, shares);
        emit Withdraw(caller, owner, assets, shares);
    }

    /**
     * @notice Delegate GRT to the indexer
     * @param delegator Address of the delegator
     * @param indexer Address of the indexer
     * @param GRTAmount Amount of GRT
     */

    function _delegate(address _theGraphStaking, address delegator, address indexer, uint256 GRTAmount)
        private
        returns (uint256 shares)
    {
        SafeERC20.safeTransfer(IERC20(asset()), delegator, GRTAmount);
        bytes memory data = abi.encodeWithSelector(IGraphStaking.delegate.selector, indexer, GRTAmount);
        bytes memory returndata = Delegator(delegator).execute(_theGraphStaking, data, 0);
        return abi.decode(returndata, (uint256));
    }
    /**
     * @dev combine multiple requests into a task for handling.
     * @param ids NFT tokenIds of the withdraw requests
     */

    function _requestUndelegate(uint256[] memory ids) private returns (uint40) {
        uint256 maxNum = ids.length;
        if (maxNum == 0) revert InvalidParam();
        GStakeStorage storage $ = _getGStakeStorage();

        uint256 _timestamp = block.timestamp;
        // the create time of the order must less than the deadline, ensuring a sufficient interval for matching.
        uint256 deadline = _timestamp - $.maxRequestPendingTime;

        uint40 _undelegateId = $.undelegationId + 1;
        $.undelegationId = _undelegateId;

        uint256 i = 0;
        uint256 totalGRT = 0;
        while (i < maxNum) {
            uint256 _tokenId = ids[i];
            WithdrawalRequest memory request = $.withdrawRequests[_tokenId];
            if (deadline < request.timestamp || request.status != WRStatus.Processing) revert UndelegateError(_tokenId);
            totalGRT += request.amountOfGRT;
            $.withdrawRequests[_tokenId].status = WRStatus.Undelegating;
            $.withdrawRequests[_tokenId].undelegateId = _undelegateId;
            ++i;
        }
        if (totalGRT == 0) {
            revert NotNeedUndelegate();
        }

        uint256 _pending = $.pendingGRT;
        if (_pending >= totalGRT) revert InvalidAmount();
        uint256 debt = $.withdrawDebt;
        if (totalGRT > debt) revert InvalidAmount();
        emit RequestUndelegate(_undelegateId, totalGRT, _pending, _timestamp, ids);

        // update pool state
        $.withdrawDebt = debt - _pending;
        $.pendingGRT = 0;
        $.lockedGRT += _pending;
        UndelegateInfo storage info = $.undelegations[_undelegateId];
        info.amountOfGRT = totalGRT - _pending;
        info.lockedGRT = _pending;
        info.timestamp = uint40(_timestamp);
        return _undelegateId;
    }

    /**
     * @notice Handle the reward fee from delegating to the graph
     * @dev Will repledge GRT, exchange it for wstGRT and give it to the treasury
     *  totalPooledGRTWithRewards = oldTotalAssets() + reward
     *  newShares * newGRTPerShare = (reward * feeRate) / MAX_PPM
     *  newGRTPerShare = totalPooledGRTWithRewards / (totalSupply + newShares)
     *  which follows to:
     *
     *                         reward * feeRate * totalSupply
     *  newShares = --------------------------------------------------------------
     *                  (totalPooledGRTWithRewards * MAX_PPM) - (reward * feeRate)
     * @param _reward Amount of GRT reward
     */
    function _handleRewardFee(GStakeStorage storage $, uint256 _reward) private {
        if (_reward > 0) {
            $.stakedGRT += _reward;
            uint256 newShares = _reward * $.feeRate * totalSupply() / (totalAssets() * MAX_PPM - (_reward * $.feeRate));
            if (newShares > 0) {
                _mint($.treasury, newShares);
                emit Deposit(address(this), $.treasury, _reward * $.feeRate / MAX_PPM, newShares);
            }
        }
    }

    /**
     * @notice Update the rewards for the corresponding delegator
     * @param _theGraphStaking Address of the graph staking
     * @param delegator Address of the delegator
     */
    function _updateReward(GStakeStorage storage $, address _theGraphStaking, address delegator)
        private
        returns (uint256 reward)
    {
        DelegatorInfo memory delegatorInfo = $.delegatorInfo[delegator];
        if (delegatorInfo.indexer == address(0)) {
            return 0;
        }
        IGraphStaking.DelegationPoolReturn memory _pool =
            IGraphStaking(_theGraphStaking).delegationPools(delegatorInfo.indexer);
        uint256 _GRTPerShare = _pool.tokens * E18_PRECISION_BASE / _pool.shares;
        if (_GRTPerShare > delegatorInfo.lastGRTPerShare) {
            uint256 _reward = (_GRTPerShare - delegatorInfo.lastGRTPerShare) * delegatorInfo.shares / E18_PRECISION_BASE;
            if (_reward > 0) {
                $.delegatorInfo[delegator].lastGRTPerShare = _GRTPerShare;
                reward = _reward;
                emit RewardUpdated(delegator, delegatorInfo.indexer, reward);
            }
        }
    }

    /**
     * @notice Delegator executes redemption process
     * @param amountOfGRT NFT tokenId of withdraw request
     */
    function _undelegate(address _theGraphStaking, address delegator, address indexer, uint256 shares)
        private
        returns (uint256 amountOfGRT)
    {
        IGraphStaking.Delegation memory _delegation = IGraphStaking(_theGraphStaking).getDelegation(indexer, delegator);
        if (_delegation.tokensLocked > 0) revert Undelegated(indexer, delegator);
        bytes memory data = abi.encodeWithSelector(IGraphStaking.undelegate.selector, indexer, shares);
        bytes memory returndata = Delegator(delegator).execute(_theGraphStaking, data, 0);
        return abi.decode(returndata, (uint256));
    }

    /**
     * @notice delete corresponding request after successful processing of the withdraw request
     * @param tokenId NFT tokenId of withdraw request
     */
    function _deleteRequest(uint256 tokenId) private {
        GStakeStorage storage $ = _getGStakeStorage();
        delete $.withdrawRequests[tokenId];
        IWithdrawalNFT($.withdrawQueue).burn(tokenId);
    }

    /**
     * @notice Check the number of GRTs to be redeemed
     * @dev the graph requires each delegator to keep at least one GRT
     * @param amountOfGRT Amount of GRT
     */
    function checkWithdrawalRequestAmount(uint256 amountOfGRT) public view {
        if (amountOfGRT < 1e16) revert RequestAmountTooSmall();
        // check withdraw limit
        GStakeStorage storage $ = _getGStakeStorage();
        if ($.nextUndelegatorIndex < $.delegators.length) {
            DelegatorInfo memory info = $.delegatorInfo[$.delegators[$.nextUndelegatorIndex]];
            uint256 totalGRT = info.shares * info.lastGRTPerShare / E18_PRECISION_BASE;
            if (totalGRT == 0) {
                return;
            }
            if (totalGRT + $.pendingGRT < $.withdrawDebt + MINIMUM_DELEGATION) revert RequestTooMuch();
        }
    }
}
