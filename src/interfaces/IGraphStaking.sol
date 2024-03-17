// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGraphStaking {


    /**
     * @notice Delegate tokens to an indexer.
     * @param _indexer Address of the indexer to which tokens are delegated
     * @param _tokens Amount of tokens to delegate
     * @return Amount of shares issued from the delegation pool
     */
    function delegate(address _indexer, uint256 _tokens) external returns (uint256);

    /**
     * @notice Undelegate tokens from an indexer. Tokens will be locked for the unbonding period.
     * @param _indexer Address of the indexer to which tokens had been delegated
     * @param _shares Amount of shares to return and undelegate tokens
     * @return Amount of tokens returned for the shares of the delegation pool
     */
    function undelegate(address _indexer, uint256 _shares) external returns (uint256);

    /**
     * @notice Withdraw undelegated tokens once the unbonding period has passed, and optionally
     * re-delegate to a new indexer.
     * @param _indexer Withdraw available tokens delegated to indexer
     * @param _newIndexer Re-delegate to indexer address if non-zero, withdraw if zero address
     */
    function withdrawDelegated(address _indexer, address _newIndexer) external returns (uint256);

    /**
     * @dev Individual delegation data of a delegator in a pool.
     */
    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
        uint256 tokensLocked; // Tokens locked for undelegation
        uint256 tokensLockedUntil; // Block when locked tokens can be withdrawn
    }

    struct DelegationPoolReturn {
        uint32 cooldownBlocks; // Blocks to wait before updating parameters
        uint32 indexingRewardCut; // in PPM
        uint32 queryFeeCut; // in PPM
        uint256 updatedAtBlock; // Block when the pool was last updated
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
    }

    /**
     * @notice Returns amount of delegated tokens ready to be withdrawn after unbonding period.
     * @param _delegation Delegation of tokens from delegator to indexer
     * @return Amount of tokens to withdraw
     */
    function getWithdraweableDelegatedTokens(Delegation memory _delegation) external view returns (uint256);

    /**
     * @notice Getter for delegationPools[_indexer]:
     * gets the delegation pool structure for a particular indexer.
     * @param _indexer Address of the indexer for which to query the delegation pool
     * @return Delegation pool as a DelegationPoolReturn struct
     */
    function delegationPools(address _indexer) external view returns (DelegationPoolReturn memory);

    function getDelegation(address _indexer, address _delegator)
        external
        view
        returns (Delegation memory);

    function delegationTaxPercentage() external view returns (uint32);
}
