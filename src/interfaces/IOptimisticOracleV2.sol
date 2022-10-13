// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title Optimistic Oracle V2
interface IOptimisticOracleV2 {
    struct RequestSettings {
        bool eventBased; // True if the request is set to be event-based.
        bool refundOnDispute; // True if the requester should be refunded their reward on dispute.
        bool callbackOnPriceProposed; // True if callbackOnPriceProposed callback is required.
        bool callbackOnPriceDisputed; // True if callbackOnPriceDisputed callback is required.
        bool callbackOnPriceSettled; // True if callbackOnPriceSettled callback is required.
        uint256 bond; // Bond that the proposer and disputer must pay on top of the final fee.
        uint256 customLiveness; // Custom liveness value set by the requester.
    }

    // Struct representing a price request.
    struct Request {
        address proposer; // Address of the proposer.
        address disputer; // Address of the disputer.
        IERC20 currency; // ERC20 token used to pay rewards and fees.
        bool settled; // True if the request is settled.
        RequestSettings requestSettings; // Custom settings associated with a request.
        int256 proposedPrice; // Price that the proposer submitted.
        int256 resolvedPrice; // Price resolved once the request is settled.
        uint256 expirationTime; // Time at which the request auto-settles without a dispute.
        uint256 reward; // Amount of the currency to pay to the proposer on settlement.
        uint256 finalFee; // Final fee to pay to the Store upon request to the DVM.
    }

    /// @notice Requests a new price.
    /// @param identifier price identifier being requested.
    /// @param timestamp timestamp of the price being requested.
    /// @param ancillaryData ancillary data representing additional args being passed with the price request.
    /// @param currency ERC20 token used for payment of rewards and fees. Must be approved for use with the DVM.
    /// @param reward reward offered to a successful proposer. Will be pulled from the caller. Note: this can be 0,
    ///               which could make sense if the contract requests and proposes the value in the same call or
    ///               provides its own reward system.
    /// @return totalBond default bond (final fee) + final fee that the proposer and disputer will be required to pay.
    /// This can be changed with a subsequent call to setBond().
    function requestPrice(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        IERC20 currency,
        uint256 reward
    ) external returns (uint256 totalBond);

    /**
     * @notice Proposes a price value for an existing price request.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param timestamp timestamp to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @param proposedPrice price being proposed.
     * @return totalBond the amount that's pulled from the proposer's wallet as a bond. The bond will be returned to
     * the proposer once settled if the proposal is correct.
     */
    function proposePrice(
        address requester,
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        int256 proposedPrice
    ) external returns (uint256 totalBond);

    /**
     * @notice Disputes a price value for an existing price request with an active proposal.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param timestamp timestamp to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @return totalBond the amount that's pulled from the disputer's wallet as a bond. The bond will be returned to
     * the disputer once settled if the dispute was valid (the proposal was incorrect).
     */
    function disputePrice(address requester, bytes32 identifier, uint256 timestamp, bytes memory ancillaryData)
        external
        returns (uint256 totalBond);

    /// @notice Set the proposal bond associated with a price request.
    /// @param identifier price identifier to identify the existing request.
    /// @param timestamp timestamp to identify the existing request.
    /// @param ancillaryData ancillary data of the price being requested.
    /// @param bond custom bond amount to set.
    /// @return totalBond new bond + final fee that the proposer and disputer will be required to pay. This can be
    /// changed again with a subsequent call to setBond().
    function setBond(bytes32 identifier, uint256 timestamp, bytes memory ancillaryData, uint256 bond)
        external
        returns (uint256 totalBond);

    /// @notice Sets the request to be an "event-based" request.
    /// @dev Calling this method has a few impacts on the request:
    ///
    /// 1. The timestamp at which the request is evaluated is the time of the proposal, not the timestamp associated
    ///    with the request.
    ///
    /// 2. The proposer cannot propose the "too early" value (TOO_EARLY_RESPONSE). This is to ensure that a proposer who
    ///    prematurely proposes a response loses their bond.
    ///
    /// 3. RefundoOnDispute is automatically set, meaning disputes trigger the reward to be automatically refunded to
    ///    the requesting contract.
    ///
    /// @param identifier price identifier to identify the existing request.
    /// @param timestamp timestamp to identify the existing request.
    /// @param ancillaryData ancillary data of the price being requested.
    function setEventBased(bytes32 identifier, uint256 timestamp, bytes memory ancillaryData) external;

    /// @notice Sets which callbacks should be enabled for the request.
    /// @param identifier price identifier to identify the existing request.
    /// @param timestamp timestamp to identify the existing request.
    /// @param ancillaryData ancillary data of the price being requested.
    /// @param callbackOnPriceProposed whether to enable the callback onPriceProposed.
    /// @param callbackOnPriceDisputed whether to enable the callback onPriceDisputed.
    /// @param callbackOnPriceSettled whether to enable the callback onPriceSettled.
    function setCallbacks(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        bool callbackOnPriceProposed,
        bool callbackOnPriceDisputed,
        bool callbackOnPriceSettled
    ) external;

    /**
     * @notice Attempts to settle an outstanding price request. Will revert if it isn't settleable.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param timestamp timestamp to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @return payout the amount that the "winner" (proposer or disputer) receives on settlement. This amount includes
     * the returned bonds as well as additional rewards.
     */
    function settle(address requester, bytes32 identifier, uint256 timestamp, bytes memory ancillaryData)
        external
        returns (uint256 payout);

    /// @notice Retrieves a price that was previously requested by a caller. Reverts if the request is not settled
    /// or settleable. Note: this method is not view so that this call may actually settle the price request if it
    /// hasn't been settled.
    /// @param identifier price identifier to identify the existing request.
    /// @param timestamp timestamp to identify the existing request.
    /// @param ancillaryData ancillary data of the price being requested.
    /// @return resolved price.
    ////
    function settleAndGetPrice(bytes32 identifier, uint256 timestamp, bytes memory ancillaryData)
        external
        returns (int256);

    /// @notice Gets the current data structure containing all information about a price request.
    /// @param requester sender of the initial price request.
    /// @param identifier price identifier to identify the existing request.
    /// @param timestamp timestamp to identify the existing request.
    /// @param ancillaryData ancillary data of the price being requested.
    /// @return the Request data structure.
    ////
    function getRequest(address requester, bytes32 identifier, uint256 timestamp, bytes memory ancillaryData)
        external
        view
        returns (Request memory);

    /// @notice Checks if a given request has resolved or been settled (i.e the optimistic oracle has a price).
    /// @param requester sender of the initial price request.
    /// @param identifier price identifier to identify the existing request.
    /// @param timestamp timestamp to identify the existing request.
    /// @param ancillaryData ancillary data of the price being requested.
    /// @return true if price has resolved or settled, false otherwise.
    function hasPrice(address requester, bytes32 identifier, uint256 timestamp, bytes memory ancillaryData)
        external
        view
        returns (bool);
}
