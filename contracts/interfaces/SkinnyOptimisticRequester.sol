// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Skinny Optimistic Requester
/// @notice Stripped down OptimisticRequester interface, exposing only the priceDisputed function
interface SkinnyOptimisticRequester {
    /// @notice Callback for disputes.
    /// @param identifier price identifier being requested.
    /// @param timestamp timestamp of the price being requested.
    /// @param ancillaryData ancillary data of the price being requested.
    /// @param refund refund received in the case that refundOnDispute was enabled.
    function priceDisputed(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        uint256 refund
    ) external;
}
