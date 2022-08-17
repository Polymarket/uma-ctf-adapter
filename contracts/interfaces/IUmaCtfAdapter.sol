// SPDX-License-Identifier: MIT 
pragma solidity 0.8.15;

interface IUmaCtfAdapterEE {

    error NotInitialized();
    error NotFlagged();
    error NotReadyToResolve();
    error Resolved();
    error Initialized();
    error UnsupportedToken();
    error Flagged();
    error Paused();
    error SafetyPeriodNotPassed();
    error PriceNotAvailable();
    error InvalidAncillaryData();
    error NotOptimisticOracle();
    error InvalidResolutionData();
    error InvalidPayouts();

    /// @notice Emitted when a questionID is initialized
    event QuestionInitialized(
        bytes32 indexed questionID,
        uint256 indexed requestTimestamp,
        address indexed creator,
        bytes ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    );

    /// @notice Emitted when a question is paused by an authorized user
    event QuestionPaused(bytes32 indexed questionID);

    /// @notice Emitted when a question is unpaused by an authorized user
    event QuestionUnpaused(bytes32 indexed questionID);

    /// @notice Emitted when a question is flagged by an admin for emergency resolution
    event QuestionFlagged(bytes32 indexed questionID);

    /// @notice Emitted when a question is reset
    event QuestionReset(bytes32 indexed questionID);

    /// @notice Emitted when a question is resolved
    event QuestionResolved(bytes32 indexed questionID, int256 indexed settledPrice, uint256[] payouts);

    /// @notice Emitted when a question is emergency resolved
    event QuestionEmergencyResolved(bytes32 indexed questionID, uint256[] payouts);
}

interface IUmaCtfAdapter is IUmaCtfAdapterEE {

    function initializeQuestion(bytes memory,address,uint256,uint256) external returns (bytes32);

    function resolve(bytes32) external;

    function flag(bytes32) external;

    function reset(bytes32) external;

}
