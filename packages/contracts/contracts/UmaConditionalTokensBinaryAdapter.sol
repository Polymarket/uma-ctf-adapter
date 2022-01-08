// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { TransferHelper } from "./libraries/TransferHelper.sol";

import { FinderInterface } from "./interfaces/FinderInterface.sol";
import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { OptimisticOracleInterface } from "./interfaces/OptimisticOracleInterface.sol";
import { AddressWhitelistInterface } from "./interfaces/AddressWhitelistInterface.sol";

/// @title UmaConditionalTokensBinaryAdapter
/// @notice Enables Conditional Token resolution via UMA's Optimistic Oracle
contract UmaConditionalTokensBinaryAdapter is ReentrancyGuard {
    /// @notice Auth
    mapping(address => uint256) public wards;

    /// @notice Authorizes a user
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit AuthorizedUser(usr);
    }

    /// @notice Deauthorizes a user
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit DeauthorizedUser(usr);
    }

    event AuthorizedUser(address indexed usr);
    event DeauthorizedUser(address indexed usr);

    /// @notice - Authorization modifier
    modifier auth() {
        require(wards[msg.sender] == 1, "Adapter/not-authorized");
        _;
    }

    /// @notice Conditional Tokens
    IConditionalTokens public immutable conditionalTokenContract;

    /// @notice UMA Finder address
    address public umaFinder;

    /// @notice Unique query identifier for the Optimistic Oracle
    bytes32 public constant identifier = "YES_OR_NO_QUERY";

    /// @notice Time period after which an authorized user can emergency resolve a condition
    uint256 public constant emergencySafetyPeriod = 2 days;

    struct QuestionData {
        // Unix timestamp(in seconds) at which a market can be resolved
        uint256 resolutionTime;
        // Reward offered to a successful proposer
        uint256 reward;
        // Additional bond required by Optimistic oracle proposers and disputers
        uint256 proposalBond;
        // Flag marking the block number when a question was settled
        uint256 settled;
        // Early Resolution timestamp, set when an early resolution data request is sent
        uint256 earlyResolutionTimestamp;
        // Flag marking whether a question can be resolved early
        bool earlyResolutionEnabled;
        // Flag marking whether resolution data has been requested from the Oracle
        bool resolutionDataRequested;
        // Flag marking whether a question is resolved
        bool resolved;
        // Flag marking whether a question is paused
        bool paused;
        // ERC20 token address used for payment of rewards and fees
        address rewardToken;
        // Data used to resolve a condition
        bytes ancillaryData;
    }

    /// @notice Mapping of questionID to QuestionData
    mapping(bytes32 => QuestionData) public questions;

    /*
    ////////////////////////////////////////////////////////////////////
                            EVENTS 
    ////////////////////////////////////////////////////////////////////
    */

    /// @notice Emitted when the UMA Finder is changed
    event NewFinderAddress(address oldFinder, address newFinder);

    /// @notice Emitted when a questionID is initialized
    event QuestionInitialized(
        bytes32 indexed questionID,
        bytes ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        bool earlyResolutionEnabled
    );

    /// @notice Emitted when a questionID is updated
    event QuestionUpdated(
        bytes32 indexed questionID,
        bytes ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        bool earlyResolutionEnabled
    );

    /// @notice Emitted when a question is paused by an authorized user
    event QuestionPaused(bytes32 questionID);

    /// @notice Emitted when a question is unpaused by an authorized user
    event QuestionUnpaused(bytes32 questionID);

    /// @notice Emitted when resolution data is requested from the Optimistic Oracle
    event ResolutionDataRequested(
        address indexed requestor,
        uint256 indexed resolutionTimestamp,
        bytes32 indexed questionID,
        bytes32 identifier,
        bytes ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        bool earlyResolution
    );

    /// @notice Emitted when a question is reset
    event QuestionReset(bytes32 indexed questionID);

    /// @notice Emitted when a question is settled
    event QuestionSettled(bytes32 indexed questionID, int256 indexed settledPrice, bool indexed earlyResolution);

    /// @notice Emitted when a question is resolved
    event QuestionResolved(bytes32 indexed questionID, bool indexed emergencyReport);

    constructor(address conditionalTokenAddress, address umaFinderAddress) {
        wards[msg.sender] = 1;
        emit AuthorizedUser(msg.sender);
        conditionalTokenContract = IConditionalTokens(conditionalTokenAddress);
        umaFinder = umaFinderAddress;
    }

    /*
    ////////////////////////////////////////////////////////////////////
                            PUBLIC 
    ////////////////////////////////////////////////////////////////////
    */

    /// @notice Initializes a question on the Adapter to report on
    /// @param questionID               - The unique questionID of the question
    /// @param ancillaryData            - Data used to resolve a question
    /// @param resolutionTime           - Timestamp after which the Adapter can resolve a question
    /// @param rewardToken              - ERC20 token address used for payment of rewards and fees
    /// @param reward                   - Reward offered to a successful proposer
    /// @param proposalBond             - Bond required to be posted by a price proposer and disputer
    /// @param earlyResolutionEnabled   - Determines whether a question can be resolved early
    function initializeQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        bool earlyResolutionEnabled
    ) public {
        require(!isQuestionInitialized(questionID), "Adapter::initializeQuestion: Question already initialized");
        require(resolutionTime > 0, "Adapter::initializeQuestion: resolutionTime must be positive");
        require(supportedToken(rewardToken), "Adapter::unsupported currency");

        questions[questionID] = QuestionData({
            ancillaryData: ancillaryData,
            resolutionTime: resolutionTime,
            rewardToken: rewardToken,
            reward: reward,
            proposalBond: proposalBond,
            earlyResolutionEnabled: earlyResolutionEnabled,
            resolutionDataRequested: false,
            resolved: false,
            paused: false,
            settled: 0,
            earlyResolutionTimestamp: 0
        });

        emit QuestionInitialized(
            questionID,
            ancillaryData,
            resolutionTime,
            rewardToken,
            reward,
            proposalBond,
            earlyResolutionEnabled
        );
    }

    /// @notice Checks whether or not a question can start the resolution process
    /// @param questionID - The unique questionID of the question
    function readyToRequestResolution(bytes32 questionID) public view returns (bool) {
        if (!isQuestionInitialized(questionID)) {
            return false;
        }
        QuestionData storage questionData = questions[questionID];
        if (questionData.resolutionDataRequested) {
            return false;
        }
        if (questionData.resolved) {
            return false;
        }
        if (questionData.earlyResolutionEnabled) {
            return true;
        }
        return block.timestamp > questionData.resolutionTime;
    }

    /// @notice Request resolution data from the Optimistic Oracle
    /// @param questionID - The unique questionID of the question
    function requestResolutionData(bytes32 questionID) public nonReentrant {
        require(
            readyToRequestResolution(questionID),
            "Adapter::requestResolutionData: Question not ready to be resolved"
        );
        QuestionData storage questionData = questions[questionID];
        require(!questionData.paused, "Adapter::requestResolutionData: Question is paused");

        // Determine if a request for resolution data is an early resolution or the standard resolution flow
        if (questionData.earlyResolutionEnabled && block.timestamp < questionData.resolutionTime) {
            return _earlyResolutionRequest(questionID, questionData);
        }
        return _standardRequest(questionID, questionData);
    }

    /// @notice Requests data from the Optimistic Oracle using the standard process
    /// @param questionID   - The unique questionID of the question
    /// @param questionData - The questionData of the question
    function _standardRequest(bytes32 questionID, QuestionData storage questionData) internal {
        // Request a price
        _requestPrice(
            msg.sender,
            identifier,
            questionData.resolutionTime,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond
        );

        // Update the resolutionDataRequested flag
        questionData.resolutionDataRequested = true;

        emit ResolutionDataRequested(
            msg.sender,
            questionData.resolutionTime,
            questionID,
            identifier,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond,
            false
        );
    }

    /// @notice Requests data from the Optimistic Oracle using early resolution
    /// @param questionID   - The unique questionID of the question
    /// @param questionData - The questionData of the question
    function _earlyResolutionRequest(bytes32 questionID, QuestionData storage questionData) internal {
        uint256 earlyResolutionTimestamp = block.timestamp;

        // Request a price
        _requestPrice(
            msg.sender,
            identifier,
            earlyResolutionTimestamp,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond
        );

        // Update early resolution timestamp and resolution data requested flag
        questionData.earlyResolutionTimestamp = earlyResolutionTimestamp;
        questionData.resolutionDataRequested = true;

        emit ResolutionDataRequested(
            msg.sender,
            questionData.earlyResolutionTimestamp,
            questionID,
            identifier,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond,
            true
        );
    }

    /// @notice Request a price from the Optimistic Oracle
    function _requestPrice(
        address requestor,
        bytes32 priceIdentifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond
    ) internal {
        // Fetch the optimistic oracle
        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        // If non-zero reward, pay for the price request by transferring rewardToken from the requestor
        if (reward > 0) {
            TransferHelper.safeTransferFrom(rewardToken, requestor, address(this), reward);

            // Approve the OO to transfer the reward token from the Adapter
            if (IERC20(rewardToken).allowance(address(this), address(optimisticOracle)) < type(uint256).max) {
                TransferHelper.safeApprove(rewardToken, address(optimisticOracle), type(uint256).max);
            }
        }

        // Send a price request to the Optimistic oracle
        optimisticOracle.requestPrice(priceIdentifier, timestamp, ancillaryData, IERC20(rewardToken), reward);

        // Update the proposal bond on the Optimistic oracle if necessary
        if (bond > 0) {
            optimisticOracle.setBond(priceIdentifier, timestamp, ancillaryData, bond);
        }
    }

    /// @notice Checks whether a questionID is ready to be settled
    /// @param questionID - The unique questionID of the question
    function readyToSettle(bytes32 questionID) public view returns (bool) {
        if (!isQuestionInitialized(questionID)) {
            return false;
        }
        QuestionData storage questionData = questions[questionID];
        // Ensure resolution data has been requested for question
        if (questionData.resolutionDataRequested == false) {
            return false;
        }
        // Ensure question has not been resolved
        if (questionData.resolved == true) {
            return false;
        }
        // Ensure question has not been settled
        if (questionData.settled != 0) {
            return false;
        }

        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        return
            optimisticOracle.hasPrice(
                address(this),
                identifier,
                _getTimestamp(questionData),
                questionData.ancillaryData
            );
    }

    /// @notice Settle/finalize the resolution data of a question
    /// @notice If the OO returns the ignore price, this method resets the question, allowing new price requests
    /// @param questionID - The unique questionID of the question
    function settle(bytes32 questionID) public {
        require(readyToSettle(questionID), "Adapter::settle: questionID is not ready to be settled");
        QuestionData storage questionData = questions[questionID];
        require(!questionData.paused, "Adapter::settle: Question is paused");

        if (questionData.earlyResolutionEnabled && questionData.earlyResolutionTimestamp > 0) {
            return _earlySettle(questionID, questionData);
        }
        return _standardSettle(questionID, questionData);
    }

    function _standardSettle(bytes32 questionID, QuestionData storage questionData) internal {
        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        int256 proposedPrice = optimisticOracle
            .getRequest(address(this), identifier, questionData.resolutionTime, questionData.ancillaryData)
            .proposedPrice;

        // NOTE: If the proposed price is the ignore price, reset the question, allowing new resolution requests
        if (proposedPrice == ignorePrice()) {
            _resetQuestion(questionID, questionData, optimisticOracle);
            return;
        }

        // Set the settled block number
        questionData.settled = block.number;

        // Settle the price
        int256 settledPrice = optimisticOracle.settleAndGetPrice(
            identifier,
            questionData.resolutionTime,
            questionData.ancillaryData
        );
        emit QuestionSettled(questionID, settledPrice, false);
    }

    function _earlySettle(bytes32 questionID, QuestionData storage questionData) internal {
        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        // Fetch the current proposed price from the OO
        int256 proposedPrice = optimisticOracle
            .getRequest(address(this), identifier, questionData.earlyResolutionTimestamp, questionData.ancillaryData)
            .proposedPrice;

        // NOTE: If the proposed price is the ignore price, reset the question, allowing new resolution requests
        if (proposedPrice == ignorePrice()) {
            _resetQuestion(questionID, questionData, optimisticOracle);
            return;
        }

        // Set the settled block number
        questionData.settled = block.number;

        // Settle the price
        int256 settledPrice = optimisticOracle.settleAndGetPrice(
            identifier,
            questionData.earlyResolutionTimestamp,
            questionData.ancillaryData
        );
        emit QuestionSettled(questionID, settledPrice, true);
    }

    function _resetQuestion(
        bytes32 questionID,
        QuestionData storage questionData,
        OptimisticOracleInterface optimisticOracle
    ) internal {
        optimisticOracle.settleAndGetPrice(identifier, _getTimestamp(questionData), questionData.ancillaryData);

        questionData.earlyResolutionTimestamp = 0;
        questionData.resolutionDataRequested = false;

        emit QuestionReset(questionID);
    }

    function _getTimestamp(QuestionData storage questionData) internal view returns (uint256) {
        if (questionData.earlyResolutionEnabled && questionData.earlyResolutionTimestamp > 0) {
            return questionData.earlyResolutionTimestamp;
        }
        return questionData.resolutionTime;
    }

    /// @notice Retrieves the expected payout of a settled question
    /// @param questionID - The unique questionID of the question
    function getExpectedPayouts(bytes32 questionID) public view returns (uint256[] memory) {
        require(isQuestionInitialized(questionID), "Adapter::getExpectedPayouts: questionID is not initialized");
        QuestionData storage questionData = questions[questionID];

        require(
            questionData.resolutionDataRequested,
            "Adapter::getExpectedPayouts: resolutionData has not been requested"
        );
        require(!questionData.resolved, "Adapter::getExpectedPayouts: questionID is already resolved");
        require(questionData.settled > 0, "Adapter::getExpectedPayouts: questionID is not settled");
        require(!questionData.paused, "Adapter::getExpectedPayouts: Question is paused");

        // Fetches resolution data from OO
        int256 resolutionData = getExpectedResolutionData(questionData);

        // Payouts: [YES, NO]
        uint256[] memory payouts = new uint256[](2);

        // Valid prices are 0, 0.5 and 1
        require(
            resolutionData == 0 || resolutionData == 0.5 ether || resolutionData == 1 ether,
            "Adapter::reportPayouts: Invalid resolution data"
        );

        if (resolutionData == 0) {
            // NO: Report [Yes, No] as [0, 1]
            payouts[0] = 0;
            payouts[1] = 1;
        } else if (resolutionData == 0.5 ether) {
            // UNKNOWN: Report [Yes, No] as [1, 1], 50/50
            payouts[0] = 1;
            payouts[1] = 1;
        } else {
            // YES: Report [Yes, No] as [1, 0]
            payouts[0] = 1;
            payouts[1] = 0;
        }
        return payouts;
    }

    function getExpectedResolutionData(QuestionData storage questionData) internal view returns (int256) {
        return
            getOptimisticOracle()
                .getRequest(address(this), identifier, _getTimestamp(questionData), questionData.ancillaryData)
                .resolvedPrice;
    }

    /// @notice Resolves a question
    /// @param questionID - The unique questionID of the question
    function reportPayouts(bytes32 questionID) public {
        QuestionData storage questionData = questions[questionID];

        // Payouts: [YES, NO]
        // getExpectedPayouts verifies that questionID is settled and can be resolved
        uint256[] memory payouts = getExpectedPayouts(questionID);

        require(
            block.number > questionData.settled,
            "Adapter::reportPayouts: Attempting to settle and reportPayouts in the same block"
        );

        questionData.resolved = true;
        conditionalTokenContract.reportPayouts(questionID, payouts);
        emit QuestionResolved(questionID, false);
    }

    /*
    ////////////////////////////////////////////////////////////////////
                            AUTHORIZED ONLY FUNCTIONS 
    ////////////////////////////////////////////////////////////////////
    */

    /// @notice Allows an authorized user to update a question
    /// @param questionID             - The unique questionID of the question
    /// @param ancillaryData          - Data used to resolve a question
    /// @param resolutionTime         - Timestamp after which the Adapter can resolve a question
    /// @param rewardToken            - ERC20 token address used for payment of rewards and fees
    /// @param reward                 - Reward offered to a successful proposer
    /// @param proposalBond           - Bond required to be posted by a price proposer and disputer
    /// @param earlyResolutionEnabled - Determines whether a question can be resolved early
    function updateQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        bool earlyResolutionEnabled
    ) external auth {
        require(isQuestionInitialized(questionID), "Adapter::updateQuestion: Question not initialized");
        require(resolutionTime > 0, "Adapter::updateQuestion: resolutionTime must be positive");
        require(supportedToken(rewardToken), "Adapter::unsupported currency");
        require(questions[questionID].settled == 0, "Adapter::updateQuestion: Question is already settled");

        questions[questionID] = QuestionData({
            ancillaryData: ancillaryData,
            resolutionTime: resolutionTime,
            rewardToken: rewardToken,
            reward: reward,
            proposalBond: proposalBond,
            earlyResolutionEnabled: earlyResolutionEnabled,
            resolutionDataRequested: false,
            resolved: false,
            paused: false,
            settled: 0,
            earlyResolutionTimestamp: 0
        });

        emit QuestionUpdated(
            questionID,
            ancillaryData,
            resolutionTime,
            rewardToken,
            reward,
            proposalBond,
            earlyResolutionEnabled
        );
    }

    /// @notice Allows an authorized user to report payouts in an emergency
    /// @param questionID - The unique questionID of the question
    function emergencyReportPayouts(bytes32 questionID, uint256[] calldata payouts) external auth {
        require(isQuestionInitialized(questionID), "Adapter::emergencyReportPayouts: questionID is not initialized");

        require(
            block.timestamp > questions[questionID].resolutionTime + emergencySafetyPeriod,
            "Adapter::emergencyReportPayouts: safety period has not passed"
        );

        require(payouts.length == 2, "Adapter::emergencyReportPayouts: payouts must be binary");

        QuestionData storage questionData = questions[questionID];

        questionData.resolved = true;
        conditionalTokenContract.reportPayouts(questionID, payouts);
        emit QuestionResolved(questionID, true);
    }

    /// @notice Allows an authorized user to pause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function pauseQuestion(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), "Adapter::pauseQuestion: questionID is not initialized");
        QuestionData storage questionData = questions[questionID];

        questionData.paused = true;
        emit QuestionPaused(questionID);
    }

    /// @notice Allows an authorized user to unpause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function unPauseQuestion(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), "Adapter::unPauseQuestion: questionID is not initialized");
        QuestionData storage questionData = questions[questionID];
        questionData.paused = false;
        emit QuestionUnpaused(questionID);
    }

    /// @notice Allows an authorized user to update the UMA Finder address
    /// @param newFinderAddress - The new finder address
    function setFinderAddress(address newFinderAddress) external auth {
        emit NewFinderAddress(umaFinder, newFinderAddress);
        umaFinder = newFinderAddress;
    }

    /*
    ////////////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS 
    ////////////////////////////////////////////////////////////////////
    */

    /// @notice Utility function that atomically prepares a question on the Conditional Tokens contract
    ///         and initializes it on the Adapter
    /// @dev Prepares the condition using the Adapter as the oracle and a fixed outcomeSlotCount
    /// @param questionID               - The unique questionID of the question
    /// @param ancillaryData            - Data used to resolve a question
    /// @param resolutionTime           - Timestamp after which the Adapter can resolve a question
    /// @param rewardToken              - ERC20 token address used for payment of rewards and fees
    /// @param reward                   - Reward offered to a successful proposer
    /// @param proposalBond             - Bond required to be posted by a price proposer and disputer
    /// @param earlyResolutionEnabled   - Determines whether a question can be resolved early
    function prepareAndInitialize(
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        bool earlyResolutionEnabled
    ) public {
        conditionalTokenContract.prepareCondition(address(this), questionID, 2);
        initializeQuestion(
            questionID,
            ancillaryData,
            resolutionTime,
            rewardToken,
            reward,
            proposalBond,
            earlyResolutionEnabled
        );
    }

    /// @notice Utility function that verifies if a question is initialized
    /// @param questionID - The unique questionID
    function isQuestionInitialized(bytes32 questionID) public view returns (bool) {
        return questions[questionID].resolutionTime > 0;
    }

    /// @notice Price that indicates that the OO does not have a valid price yet
    function ignorePrice() public pure returns (int256) {
        return type(int256).min;
    }

    function getOptimisticOracleAddress() internal view returns (address) {
        return FinderInterface(umaFinder).getImplementationAddress("OptimisticOracle");
    }

    function getOptimisticOracle() internal view returns (OptimisticOracleInterface) {
        return OptimisticOracleInterface(getOptimisticOracleAddress());
    }

    function getCollateralWhitelistAddress() internal view returns (address) {
        return FinderInterface(umaFinder).getImplementationAddress("CollateralWhitelist");
    }

    function supportedToken(address token) internal view returns (bool) {
        return AddressWhitelistInterface(getCollateralWhitelistAddress()).isOnWhitelist(token);
    }
}
