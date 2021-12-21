// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FinderInterface } from "./interfaces/FinderInterface.sol";
import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { OptimisticOracleInterface } from "./interfaces/OptimisticOracleInterface.sol";

/// @title UmaConditionalTokensBinaryAdapter
/// @notice Adapter contract that enables conditional token resolution via UMA's Optimistic Oracle
contract UmaConditionalTokensBinaryAdapter {
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

    /// @notice Time period after which an admin can emergency resolve a condition
    uint256 public constant emergencySafetyPeriod = 30 days;

    struct QuestionData {
        // Unix timestamp(in seconds) at which a market can be resolved
        uint256 resolutionTime;
        // Reward offered to a successful proposer
        uint256 reward;
        // Additional bond required by Optimistic oracle proposers and disputers
        uint256 proposalBond;
        // Flag marking the block number when a question was settled
        uint256 settled;
        // Early expiry timestamp, set when an early expiry data request is sent
        uint256 earlyExpiryTimestamp;
        // Flag marking whether a question can be resolved early
        bool earlyExpiryEnabled;
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

    // Events

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
        bool earlyExpiryEnabled
    );

    /// @notice Emitted when a question is paused by the Admin
    event QuestionPaused(bytes32 questionID);

    /// @notice Emitted when a question is unpaused by the Admin
    event QuestionUnpaused(bytes32 questionID);

    /// @notice Emitted when resolution data is requested from the Optimistic Oracle
    event ResolutionDataRequested(
        bytes32 indexed identifier,
        uint256 indexed resolutionTimestamp,
        bytes32 indexed questionID,
        bytes ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        bool earlyExpiry
    );

    /// @notice Emitted when a question is settled
    event QuestionSettled(bytes32 indexed questionID, bool indexed earlyExpiry);

    /// @notice Emitted when a question is resolved
    event QuestionResolved(bytes32 indexed questionID, bool indexed emergencyReport);

    constructor(address conditionalTokenAddress, address umaFinderAddress) {
        wards[msg.sender] = 1;
        emit AuthorizedUser(msg.sender);
        conditionalTokenContract = IConditionalTokens(conditionalTokenAddress);
        umaFinder = umaFinderAddress;
    }

    /// @notice Initializes a question on the Adapter to report on
    /// @param questionID           - The unique questionID of the question
    /// @param ancillaryData        - Holds data used to resolve a question
    /// @param resolutionTime       - Timestamp at which the Adapter can resolve a question
    /// @param rewardToken          - ERC20 token address used for payment of rewards and fees
    /// @param reward               - Reward offered to a successful proposer
    /// @param proposalBond         - Bond required to be posted by a price proposer and disputer
    /// @param earlyExpiryEnabled   - Param that determines whether a question can be expired early
    function initializeQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        bool earlyExpiryEnabled
    ) public {
        require(!isQuestionInitialized(questionID), "Adapter::initializeQuestion: Question already initialized");
        questions[questionID] = QuestionData({
            ancillaryData: ancillaryData,
            resolutionTime: resolutionTime,
            rewardToken: rewardToken,
            reward: reward,
            proposalBond: proposalBond,
            earlyExpiryEnabled: earlyExpiryEnabled,
            resolutionDataRequested: false,
            resolved: false,
            paused: false,
            settled: 0,
            earlyExpiryTimestamp: 0
        });

        // Approve the OO to transfer the reward token
        address optimisticOracleAddress = getOptimisticOracleAddress();
        IERC20(rewardToken).approve(optimisticOracleAddress, reward);
        emit QuestionInitialized(
            questionID,
            ancillaryData,
            resolutionTime,
            rewardToken,
            reward,
            proposalBond,
            earlyExpiryEnabled
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
        if (questionData.earlyExpiryEnabled) {
            return true;
        }
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp > questionData.resolutionTime;
    }

    /// @notice Request resolution data from the Optimistic Oracle
    /// @param questionID - The unique questionID of the question
    function requestResolutionData(bytes32 questionID) public {
        require(
            readyToRequestResolution(questionID),
            "Adapter::requestResolutionData: Question not ready to be resolved"
        );
        QuestionData storage questionData = questions[questionID];
        require(!questionData.paused, "Adapter::requestResolutionData: Question is paused");

        // Determine if a request for resolution data is an early expiry or the standard settlement flow
        if (isEarlyExpiry(questionID)) {
            return _earlyExpiryRequest(questionID, questionData);
        }
        return _standardRequest(questionID, questionData);
    }

    /// @notice Requests data from the Optimistic Oracle using the standard process
    /// @param questionID   - The unique questionID of the question
    /// @param questionData - The questionData of the question
    function _standardRequest(bytes32 questionID, QuestionData storage questionData) internal {
        // Request a price
        _requestPrice(
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
            identifier,
            questionData.resolutionTime,
            questionID,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond,
            false
        );
    }

    /// @notice Requests data from the Optimistic Oracle using early expiry
    /// @param questionID   - The unique questionID of the question
    /// @param questionData - The questionData of the question
    function _earlyExpiryRequest(bytes32 questionID, QuestionData storage questionData) internal {
        // solhint-disable-next-line not-rely-on-time
        uint256 earlyExpiryTs = block.timestamp;

        // Request a price
        _requestPrice(
            identifier,
            earlyExpiryTs,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond
        );

        // Update early expiry timestamp and resolution data requested flag
        questionData.earlyExpiryTimestamp = earlyExpiryTs;
        questionData.resolutionDataRequested = true;

        emit ResolutionDataRequested(
            identifier,
            questionData.earlyExpiryTimestamp,
            questionID,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond,
            true
        );
    }

    /// @notice Request a price from the Optimistic Oracle
    function _requestPrice(
        bytes32 priceIdentifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond
    ) internal {
        // Fetch the optimistic oracle
        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

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
        // Ensure question hasn't been resolved
        if (questionData.resolved == true) {
            return false;
        }
        // Ensure question hasn't been settled
        if (questionData.settled != 0) {
            return false;
        }

        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        if (isEarlyExpiry(questionID)) {
            return
                optimisticOracle.hasPrice(
                    address(this),
                    identifier,
                    questionData.earlyExpiryTimestamp,
                    questionData.ancillaryData
                );
        }

        return
            optimisticOracle.hasPrice(
                address(this),
                identifier,
                questionData.resolutionTime,
                questionData.ancillaryData
            );
    }

    /// @notice Settle/finalize the resolution data of a question
    /// @notice If early expiry is enabled and the OO returned the ignore price,
    ///         this method "refreshes" the question, allowing new price requests
    /// @param questionID - The unique questionID of the question
    function settle(bytes32 questionID) public {
        require(readyToSettle(questionID), "Adapter::settle: questionID is not ready to be settled");
        QuestionData storage questionData = questions[questionID];
        require(!questionData.paused, "Adapter::settle: Question is paused");

        if (isEarlyExpiry(questionID)) {
            return _earlySettle(questionID, questionData);
        }
        return _standardSettle(questionID, questionData);
    }

    function _standardSettle(bytes32 questionID, QuestionData storage questionData) internal {
        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        // Set the settled block number
        questionData.settled = block.number;

        // Settle the price
        optimisticOracle.settleAndGetPrice(identifier, questionData.resolutionTime, questionData.ancillaryData);
        emit QuestionSettled(questionID, false);
    }

    function _earlySettle(bytes32 questionID, QuestionData storage questionData) internal {
        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        // Fetch the current proposed price from the OO
        int256 proposedPrice = optimisticOracle
            .getRequest(address(this), identifier, questionData.earlyExpiryTimestamp, questionData.ancillaryData)
            .proposedPrice;

        // If the proposed price is the ignore price:
        // 1) Do not settle the price
        // 2) Set the resolution data requested flag to false, allowing a new price request to be sent for this question
        if (proposedPrice == earlyExpiryIgnorePrice()) {
            questionData.resolutionDataRequested = false;
            return;
        }

        // Set the settled block number
        questionData.settled = block.number;

        // Settle the price
        optimisticOracle.settleAndGetPrice(identifier, questionData.earlyExpiryTimestamp, questionData.ancillaryData);
        emit QuestionSettled(questionID, true);
    }

    /// @notice Can be called by anyone to retrieve the expected payout of a settled question
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
        int256 resolutionData = getExpectedResolutionData(questionID, questionData);

        // Payouts: [YES, NO]
        uint256[] memory payouts = new uint256[](2);

        // Valid prices are 0, 0.5 and 1
        require(
            resolutionData == 0 || resolutionData == 0.5 ether || resolutionData == 1 ether,
            "Adapter::reportPayouts: Invalid resolution data"
        );

        if (resolutionData == 0) {
            //NO: Report [Yes, No] as [0, 1]
            payouts[0] = 0;
            payouts[1] = 1;
        } else if (resolutionData == 0.5 ether) {
            //UNKNOWN: Report [Yes, No] as [1, 1], 50/50
            payouts[0] = 1;
            payouts[1] = 1;
        } else {
            // YES: Report [Yes, No] as [1, 0]
            payouts[0] = 1;
            payouts[1] = 0;
        }
        return payouts;
    }

    function getExpectedResolutionData(bytes32 questionID, QuestionData storage questionData)
        internal
        view
        returns (int256)
    {
        if (isEarlyExpiry(questionID)) {
            return
                getOptimisticOracle()
                    .getRequest(
                        address(this),
                        identifier,
                        questionData.earlyExpiryTimestamp,
                        questionData.ancillaryData
                    )
                    .resolvedPrice;
        }
        return
            getOptimisticOracle()
                .getRequest(address(this), identifier, questionData.resolutionTime, questionData.ancillaryData)
                .resolvedPrice;
    }

    /// @notice Can be called by anyone to resolve a question
    /// @param questionID - The unique questionID of the question
    function reportPayouts(bytes32 questionID) public {
        QuestionData storage questionData = questions[questionID];

        // Payouts: [YES, NO]
        //getExpectedPayouts verifies that questionID is settled and can be resolved
        uint256[] memory payouts = getExpectedPayouts(questionID);

        require(
            block.number > questionData.settled,
            "Adapter::reportPayouts: Attempting to settle and reportPayouts in the same block"
        );

        questionData.resolved = true;
        conditionalTokenContract.reportPayouts(questionID, payouts);
        emit QuestionResolved(questionID, false);
    }

    /// @notice Allows an admin to report payouts in an emergency
    /// @param questionID - The unique questionID of the question
    function emergencyReportPayouts(bytes32 questionID, uint256[] calldata payouts) external auth {
        require(isQuestionInitialized(questionID), "Adapter::emergencyReportPayouts: questionID is not initialized");

        require(
            // solhint-disable-next-line not-rely-on-time
            block.timestamp > questions[questionID].resolutionTime + emergencySafetyPeriod,
            "Adapter::emergencyReportPayouts: safety period has not passed"
        );

        require((payouts[0] + payouts[1]) == 1, "Adapter::emergencyReportPayouts: payouts must be binary");
        require(payouts.length == 2, "Adapter::emergencyReportPayouts: payouts must be binary");

        QuestionData storage questionData = questions[questionID];

        questionData.resolved = true;
        conditionalTokenContract.reportPayouts(questionID, payouts);
        emit QuestionResolved(questionID, true);
    }

    /// @notice Allows an admin to pause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function pauseQuestion(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), "Adapter::pauseQuestion: questionID is not initialized");
        QuestionData storage questionData = questions[questionID];

        questionData.paused = true;
        emit QuestionPaused(questionID);
    }

    /// @notice Allows an admin to unpause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function unPauseQuestion(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), "Adapter::unPauseQuestion: questionID is not initialized");
        QuestionData storage questionData = questions[questionID];
        questionData.paused = false;
        emit QuestionUnpaused(questionID);
    }

    function setFinderAddress(address newFinderAddress) external auth {
        emit NewFinderAddress(umaFinder, newFinderAddress);
        umaFinder = newFinderAddress;
    }

    function isQuestionInitialized(bytes32 questionID) public view returns (bool) {
        return questions[questionID].resolutionTime != 0;
    }

    function isEarlyExpiry(bytes32 questionID) public view returns (bool) {
        QuestionData storage questionData = questions[questionID];
        // solhint-disable-next-line not-rely-on-time
        return questionData.earlyExpiryEnabled && block.timestamp < questionData.resolutionTime;
    }

    /// @notice Special price that indicates early expiration is not ready yet
    function earlyExpiryIgnorePrice() public pure returns (int256) {
        return type(int256).min;
    }

    function getOptimisticOracleAddress() internal view returns (address) {
        return FinderInterface(umaFinder).getImplementationAddress("OptimisticOracle");
    }

    function getOptimisticOracle() internal view returns (OptimisticOracleInterface) {
        return OptimisticOracleInterface(getOptimisticOracleAddress());
    }
}
