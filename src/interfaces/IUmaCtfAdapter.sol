// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

struct QuestionData {
    /// @notice Request timestamp, set when a request is made to the Optimistic Oracle
    /// @dev Used to identify the request and NOT used by the DVM to determine validity
    uint256 requestTimestamp;
    /// @notice Reward offered to a successful proposer
    uint256 reward;
    /// @notice Additional bond required by Optimistic oracle proposers/disputers
    uint256 proposalBond;
    /// @notice Custom liveness period
    uint256 liveness;
    /// @notice Emergency resolution timestamp, set when a market is flagged for emergency resolution
    uint256 emergencyResolutionTimestamp;
    /// @notice Flag marking whether a question is resolved
    bool resolved;
    /// @notice Flag marking whether a question is paused
    bool paused;
    /// @notice Flag marking whether a question has been reset. A question can only be reset once
    bool reset;
    /// @notice ERC20 token address used for payment of rewards, proposal bonds and fees
    address rewardToken;
    /// @notice The address of the question creator
    address creator;
    /// @notice Data used to resolve a condition
    bytes ancillaryData;
}

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
    error InvalidOOPrice();
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
    function initialize(
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        uint256 liveness
    ) external returns (bytes32);

    function ready(bytes32 questionID) external view returns (bool);

    function resolve(bytes32 questionID) external;

    function flag(bytes32 questionID) external;

    function reset(bytes32 questionID) external;

    function pause(bytes32 questionID) external;

    function unpause(bytes32 questionID) external;

    function getQuestion(bytes32 questionID) external returns (QuestionData memory);
}
