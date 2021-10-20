// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { FinderInterface } from "./interfaces/FinderInterface.sol";
import { OptimisticOracleInterface } from "./interfaces/OptimisticOracleInterface.sol";

/**
 * @title UmaConditionalTokensBinaryAdapter
 * @notice allows a condition to be resolved via UMA's Optimistic Oracle
 */
contract UmaConditionalTokensBinaryAdapter is AccessControl {
    // Conditional Tokens framework
    IConditionalTokens public immutable conditionalTokenContract;

    // @notice Finder Interface for the Optimistic Oracle
    FinderInterface public umaFinder;

    // @notice Unique query identifier for the Optimistic Oracle
    bytes32 public constant identifier = "YES_OR_NO_QUERY";

    // @notice Time period after which an admin can emergency resolve a condition
    uint256 public constant emergencySafetyPeriod = 30 days;

    struct QuestionData {
        // @notice Data used to resolve a condition
        bytes ancillaryData;
        // @notice Unix timestamp(in seconds) at which a market can be resolved
        uint256 resolutionTime;
        // @notice ERC20 token address used for payment of rewards and fees
        address rewardToken;
        // @notice Reward offered to a successful proposer
        uint256 reward;
        // @notice Additional bond required by Optimistic oracle proposers and disputers
        uint256 proposalBond;
        // @notice Flag marking whether resolution data has been requested from the Oracle
        bool resolutionDataRequested;
        // @notice Flag marking whether a question is resolved
        bool resolved;
        // @notice Flag marking whether a question is paused
        bool paused;
        // @notice Flag marking the block number when a question was settled
        uint256 settled;
    }

    mapping(bytes32 => QuestionData) public questions;

    // Events
    // @notice Emitted when a questionID is initialized
    event QuestionInitialized(
        bytes32 indexed questionID,
        bytes ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    );

    // @notice Emitted when a question is paused by the Admin
    event QuestionPaused(bytes32 questionID);

    // @notice Emitted when a question is unpaused by the Admin
    event QuestionUnpaused(bytes32 questionID);

    // @notice Emitted when resolution data is requested from the Optimistic Oracle
    event ResolutionDataRequested(
        bytes32 indexed identifier,
        uint256 indexed timestamp,
        bytes32 indexed questionID,
        bytes ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    );

    // @notice Emitted when a question is settled
    event QuestionSettled(bytes32 indexed questionID);

    // @notice Emitted when a question is resolved
    event QuestionResolved(bytes32 indexed questionID, bool indexed emergencyReport);

    constructor(address conditionalTokenAddress, address umaFinderAddress) {
        conditionalTokenContract = IConditionalTokens(conditionalTokenAddress);
        umaFinder = FinderInterface(umaFinderAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Initializes a question on the Adapter to report on
     *
     * @param questionID     - The unique questionID of the question
     * @param ancillaryData  - Holds data used to resolve a question
     * @param resolutionTime - Timestamp at which the Adapter can resolve a question
     * @param rewardToken    - ERC20 token address used for payment of rewards and fees
     * @param reward         - Reward offered to a successful proposer
     * @param proposalBond   - Additional bond required to be posted by a price proposer and disputer
     */
    function initializeQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    ) public {
        require(!isQuestionInitialized(questionID), "Adapter::initializeQuestion: Question already initialized");
        questions[questionID] = QuestionData({
            ancillaryData: ancillaryData,
            resolutionTime: resolutionTime,
            rewardToken: rewardToken,
            reward: reward,
            proposalBond: proposalBond,
            resolutionDataRequested: false,
            resolved: false,
            paused: false,
            settled: 0
        });

        // Approve the OO to transfer the reward token
        address optimisticOracleAddress = getOptimisticOracleAddress();
        IERC20(rewardToken).approve(optimisticOracleAddress, reward);
        emit QuestionInitialized(questionID, ancillaryData, resolutionTime, rewardToken, reward, proposalBond);
    }

    /**
     * @notice - Checks whether or not a question can start the resolution process
     * @param questionID - The unique questionID of the question
     */
    function readyToRequestResolution(bytes32 questionID) public view returns (bool) {
        if (!isQuestionInitialized(questionID)) {
            return false;
        }
        QuestionData storage questionData = questions[questionID];
        if (questionData.resolutionDataRequested == true) {
            return false;
        }
        if (questionData.resolved == true) {
            return false;
        }
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp > questionData.resolutionTime;
    }

    /**
     * @notice Called by anyone to request resolution data from the Optimistic Oracle
     * @param questionID - The unique questionID of the question
     */
    function requestResolutionData(bytes32 questionID) public {
        require(
            readyToRequestResolution(questionID),
            "Adapter::requestResolutionData: Question not ready to be resolved"
        );
        QuestionData storage questionData = questions[questionID];
        require(!questionData.paused, "Adapter::requestResolutionData: Question is paused");

        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        questionData.resolutionDataRequested = true;

        emit ResolutionDataRequested(
            identifier,
            questionData.resolutionTime,
            questionID,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond
        );

        // Send a price request to the Optimistic oracle
        optimisticOracle.requestPrice(
            identifier,
            questionData.resolutionTime,
            questionData.ancillaryData,
            IERC20(questionData.rewardToken),
            questionData.reward
        );

        // Update the proposal bond on the Optimistic oracle if necessary
        if (questionData.proposalBond > 0) {
            optimisticOracle.setBond(
                identifier,
                questionData.resolutionTime,
                questionData.ancillaryData,
                questionData.proposalBond
            );
        }
    }

    /**
     * @notice Checks whether a questionID is ready to be settled
     * @param questionID - The unique questionID of the question
     */
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

        return
            optimisticOracle.hasPrice(
                address(this),
                identifier,
                questionData.resolutionTime,
                questionData.ancillaryData
            );
    }

    /**
     * @notice Can be called by anyone to settle/finalize the price of a question
     * @param questionID - The unique questionID of the question
     */
    function settle(bytes32 questionID) public {
        require(readyToSettle(questionID), "Adapter::settle: questionID is not ready to be settled");
        QuestionData storage questionData = questions[questionID];
        require(!questionData.paused, "Adapter::settle: Question is paused");

        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();
        questionData.settled = block.number;
        optimisticOracle.settle(address(this), identifier, questionData.resolutionTime, questionData.ancillaryData);
        emit QuestionSettled(questionID);
    }

    /**
     * @notice Can be called by anyone to retrieve the expected payout of a settled question
     * @param questionID - The unique questionID of the question
     */
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

        OptimisticOracleInterface optimisticOracle = getOptimisticOracle();

        // fetches resolution data from OO
        int256 resolutionData = optimisticOracle
            .getRequest(address(this), identifier, questionData.resolutionTime, questionData.ancillaryData)
            .resolvedPrice;

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

    /**
     * @notice Can be called by anyone to resolve a question
     * @param questionID - The unique questionID of the question
     */
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

    /**
     * @notice Allows an admin to report payouts in an emergency
     * @param questionID - The unique questionID of the question
     */
    function emergencyReportPayouts(bytes32 questionID, uint256[] calldata payouts) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Adapter::emergencyReportPayouts: caller does not have admin role"
        );
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

    /**
     * @notice Allows an admin to pause market resolution in an emergency
     * @param questionID - The unique questionID of the question
     */
    function pauseQuestion(bytes32 questionID) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Adapter::pauseQuestion: caller does not have admin role");
        require(isQuestionInitialized(questionID), "Adapter::pauseQuestion: questionID is not initialized");
        QuestionData storage questionData = questions[questionID];

        questionData.paused = true;
        emit QuestionPaused(questionID);
    }

    /**
     * @notice Allows an admin to unpause market resolution in an emergency
     * @param questionID - The unique questionID of the question
     */
    function unPauseQuestion(bytes32 questionID) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Adapter::unPauseQuestion: caller does not have admin role");
        require(isQuestionInitialized(questionID), "Adapter::unPauseQuestion: questionID is not initialized");
        QuestionData storage questionData = questions[questionID];

        questionData.paused = false;
        emit QuestionUnpaused(questionID);
    }

    function isQuestionInitialized(bytes32 questionID) public view returns (bool) {
        return questions[questionID].resolutionTime != 0;
    }

    function getOptimisticOracleAddress() internal view returns (address) {
        return umaFinder.getImplementationAddress("OptimisticOracle");
    }

    function getOptimisticOracle() internal view returns (OptimisticOracleInterface) {
        return OptimisticOracleInterface(getOptimisticOracleAddress());
    }
}
