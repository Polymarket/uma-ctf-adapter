// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { UmaConstants } from "./libraries/UmaConstants.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";

import { FinderInterface } from "./interfaces/FinderInterface.sol";
import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { OptimisticOracleV2Interface } from "./interfaces/OptimisticOracleV2Interface.sol";
import { AddressWhitelistInterface } from "./interfaces/AddressWhitelistInterface.sol";

import { Auth } from "./mixins/Auth.sol";

/// @title UmaCtfAdapter
/// @notice Enables resolution of CTF markets via UMA's Optimistic Oracle
contract UmaCtfAdapter is Auth, ReentrancyGuard {
    /*///////////////////////////////////////////////////////////////////
                            IMMUTABLES 
    //////////////////////////////////////////////////////////////////*/

    /// @notice Conditional Tokens Framework
    IConditionalTokens public immutable ctf;

    /// @notice Optimistic Oracle
    OptimisticOracleV2Interface public immutable optimisticOracle;

    /// @notice Collateral Whitelist
    AddressWhitelistInterface public immutable collateralWhitelist;

    /*///////////////////////////////////////////////////////////////////
                            CONSTANTS 
    //////////////////////////////////////////////////////////////////*/

    /// @notice Time period after which an authorized user can emergency resolve a condition
    uint256 public constant emergencySafetyPeriod = 2 days;

    struct QuestionData {
        /// @notice Request timestamp, set when a request is made to the Optimistic Oracle
        /// @dev Used to identify the request and NOT used by the DVM to determine validity
        uint256 requestTimestamp;
        /// @notice Reward offered to a successful proposer
        uint256 reward;
        /// @notice Additional bond required by Optimistic oracle proposers and disputers
        uint256 proposalBond;
        /// @notice Flag marking the block number when a question was settled
        uint256 settled;
        /// @notice Admin Resolution timestamp, set when a market is flagged for admin resolution
        uint256 adminResolutionTimestamp;
        /// @notice Flag marking whether a question is resolved
        bool resolved;
        /// @notice Flag marking whether a question is paused
        bool paused;
        /// @notice ERC20 token address used for payment of rewards, proposal bonds and fees
        address rewardToken;
        /// @notice Data used to resolve a condition
        bytes ancillaryData;
    }

    /// @notice Mapping of questionID to QuestionData
    mapping(bytes32 => QuestionData) public questions;

    /*///////////////////////////////////////////////////////////////////
                            EVENTS 
    //////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a questionID is initialized
    event QuestionInitialized(
        bytes32 indexed questionID,
        uint256 indexed requestTimestamp,
        bytes ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    );

    /// @notice Emitted when a questionID is updated
    event QuestionUpdated(
        bytes32 indexed questionID,
        uint256 requestTimestamp,
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
    event QuestionFlaggedForAdminResolution(bytes32 indexed questionID);

    /// @notice Emitted when a question is reset
    event QuestionReset(bytes32 indexed questionID);

    /// @notice Emitted when a question is settled
    event QuestionSettled(bytes32 indexed questionID, int256 indexed settledPrice);

    /// @notice Emitted when a question is resolved
    event QuestionResolved(bytes32 indexed questionID, bool indexed emergencyReport);

    constructor(address _ctf, address _finder) {
        ctf = IConditionalTokens(_ctf);
        optimisticOracle = OptimisticOracleV2Interface(
            FinderInterface(_finder).getImplementationAddress(UmaConstants.OptimisticOracleV2)
        );
        collateralWhitelist = AddressWhitelistInterface(
            FinderInterface(_finder).getImplementationAddress(UmaConstants.CollateralWhitelist)
        );
    }

    /*///////////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS 
    //////////////////////////////////////////////////////////////////*/

    /// @notice Initializes a question
    /// Atomically adds the question to the Adapter, prepares it on the CTF and requests a price from the OO.
    /// If reward > 0, caller must have approved the Adapter as spender and have enough rewardToken to pay for the price request.
    /// Prepares the condition using the Adapter as the oracle and a fixed outcomeSlotCount = 2.
    /// @param questionID    - The unique questionID of the question
    /// @param ancillaryData - Data used to resolve a question
    /// @param rewardToken   - ERC20 token address used for payment of rewards and fees
    /// @param reward        - Reward offered to a successful proposer
    /// @param proposalBond  - Bond required to be posted by a price proposer and disputer
    function initializeQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    ) external {
        require(!isQuestionInitialized(questionID), "Adapter/already-initialized");
        require(collateralWhitelist.isOnWhitelist(rewardToken), "Adapter/unsupported-token");
        require(
            ancillaryData.length > 0 && ancillaryData.length <= UmaConstants.AncillaryDataLimit,
            "Adapter/invalid-ancillary-data"
        );

        uint256 requestTimestamp = block.timestamp;

        // Save the question parameters in storage
        _saveQuestion(questionID, ancillaryData, requestTimestamp, rewardToken, reward, proposalBond);

        // Prepare the question on the CTF
        ctf.prepareCondition(address(this), questionID, 2);

        // Request a price for the question from the Optimistic oracle
        _requestPrice(
            msg.sender,
            UmaConstants.YesOrNoIdentifier,
            requestTimestamp,
            ancillaryData,
            rewardToken,
            reward,
            proposalBond
        );

        emit QuestionInitialized(questionID, requestTimestamp, ancillaryData, rewardToken, reward, proposalBond);
    }

    /// @notice Checks whether a questionID is ready to be settled
    /// @param questionID - The unique questionID of the question
    function readyToSettle(bytes32 questionID) public view returns (bool) {
        if (!isQuestionInitialized(questionID)) {
            return false;
        }

        QuestionData storage questionData = questions[questionID];

        // Ensure question has not been resolved
        if (questionData.resolved == true) {
            return false;
        }

        // Ensure question has not been settled
        if (questionData.settled != 0) {
            return false;
        }

        return
            optimisticOracle.hasPrice(
                address(this),
                UmaConstants.YesOrNoIdentifier,
                questionData.requestTimestamp,
                questionData.ancillaryData
            );
    }

    /// @notice Settle the question
    /// @param questionID - The unique questionID of the question
    function settle(bytes32 questionID) external nonReentrant {
        require(readyToSettle(questionID), "Adapter/not-ready-to-settle");

        QuestionData storage questionData = questions[questionID];
        require(!questionData.paused, "Adapter/paused");

        return _settle(questionID, questionData);
    }

    /// @notice Retrieves the expected payout of a settled question
    /// @param questionID - The unique questionID of the question
    function getExpectedPayouts(bytes32 questionID) public view returns (uint256[] memory) {
        require(isQuestionInitialized(questionID), "Adapter/not-initialized");
        QuestionData storage questionData = questions[questionID];

        require(questionData.settled > 0, "Adapter/not-settled");
        require(!questionData.paused, "Adapter/paused");

        // Fetches resolution data from OO
        int256 resolutionData = getExpectedResolutionData(questionData);

        // Payouts: [YES, NO]
        uint256[] memory payouts = new uint256[](2);

        // Valid prices are 0, 0.5 and 1
        require(
            resolutionData == 0 || resolutionData == 0.5 ether || resolutionData == 1 ether,
            "Adapter/invalid-resolution-data"
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

    /// @notice Resolves a question
    /// @param questionID - The unique questionID of the question
    function reportPayouts(bytes32 questionID) external {
        QuestionData storage questionData = questions[questionID];

        require(!questionData.resolved, "Adapter/already-resolved");
        require(block.number > questionData.settled, "Adapter/same-block-settle-report");

        // Payouts: [YES, NO]
        // getExpectedPayouts verifies that questionID is settled and can be resolved
        uint256[] memory payouts = getExpectedPayouts(questionID);

        questionData.resolved = true;
        ctf.reportPayouts(questionID, payouts);
        emit QuestionResolved(questionID, false);
    }

    /*///////////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS 
    //////////////////////////////////////////////////////////////////*/

    function _saveQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 requestTimestamp,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    ) internal {
        questions[questionID] = QuestionData({
            requestTimestamp: requestTimestamp,
            ancillaryData: ancillaryData,
            rewardToken: rewardToken,
            reward: reward,
            proposalBond: proposalBond,
            resolved: false,
            paused: false,
            settled: 0,
            adminResolutionTimestamp: 0
        });
    }

    /// @notice Request a price from the Optimistic Oracle
    /// Transfers reward token from the requestor if non-zero reward is specified
    /// @param caller           - Address of the caller
    /// @param priceIdentifier  - Bytes32 identifier for the OO
    /// @param requestTimestamp - Timestamp used in the OO request
    /// @param ancillaryData    - Data used to resolve a question
    /// @param rewardToken      - Address of the reward token
    /// @param reward           - Reward amount, denominated in rewardToken
    /// @param bond             - Bond amount used, denominated in rewardToken
    function _requestPrice(
        address caller,
        bytes32 priceIdentifier,
        uint256 requestTimestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond
    ) internal {
        // If non-zero reward, pay for the price request by transferring rewardToken from the caller
        if (reward > 0) {
            TransferHelper.safeTransferFrom(rewardToken, caller, address(this), reward);

            // Approve the OO as spender on the reward token from the Adapter
            if (IERC20(rewardToken).allowance(address(this), address(optimisticOracle)) < reward) {
                TransferHelper.safeApprove(rewardToken, address(optimisticOracle), type(uint256).max);
            }
        }

        // Send a price request to the Optimistic oracle
        optimisticOracle.requestPrice(priceIdentifier, requestTimestamp, ancillaryData, IERC20(rewardToken), reward);

        // Ensure the price request is event based
        optimisticOracle.setEventBased(priceIdentifier, requestTimestamp, ancillaryData);

        // Update the proposal bond on the Optimistic oracle if necessary
        if (bond > 0) {
            optimisticOracle.setBond(priceIdentifier, requestTimestamp, ancillaryData, bond);
        }
    }

    function _settle(bytes32 questionID, QuestionData storage questionData) internal {
        // Get the price from the OO
        int256 price = optimisticOracle.settleAndGetPrice(
            UmaConstants.YesOrNoIdentifier,
            questionData.requestTimestamp,
            questionData.ancillaryData
        );

        // TODO: if a proposer proposes prematurely, the adapter needs to re-request the price request
        //

        // Set the settled block number
        questionData.settled = block.number;

        emit QuestionSettled(questionID, price);
    }

    function _resetQuestion(bytes32 questionID, QuestionData storage questionData) internal {
        questionData.requestTimestamp = 0;
        emit QuestionReset(questionID);
    }

    function getExpectedResolutionData(QuestionData storage questionData) internal view returns (int256) {
        return
            optimisticOracle
                .getRequest(
                    address(this),
                    UmaConstants.YesOrNoIdentifier,
                    questionData.requestTimestamp,
                    questionData.ancillaryData
                )
                .resolvedPrice;
    }

    /*////////////////////////////////////////////////////////////////////
                            AUTHORIZED FUNCTIONS 
    ///////////////////////////////////////////////////////////////////*/

    /// @notice Allows an authorized user to update a question
    /// This will remove the old question data from the Adapter and send a new price request to the OO.
    /// Note: the previous price request will still exist on the OO, will not be considered by the Adapter
    /// @param questionID             - The unique questionID of the question
    /// @param ancillaryData          - Data used to resolve a question
    /// @param rewardToken            - ERC20 token address used for payment of rewards and fees
    /// @param reward                 - Reward offered to a successful proposer
    /// @param proposalBond           - Bond required to be posted by a price proposer and disputer
    function updateQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    ) external auth {
        require(isQuestionInitialized(questionID), "Adapter/not-initialized");
        require(collateralWhitelist.isOnWhitelist(rewardToken), "Adapter/unsupported-token");
        require(
            ancillaryData.length > 0 && ancillaryData.length <= UmaConstants.AncillaryDataLimit,
            "Adapter/invalid-ancillary-data"
        );
        require(questions[questionID].settled == 0, "Adapter/already-settled");

        uint256 requestTimestamp = block.timestamp;

        // Update question parameters in storage
        _saveQuestion(questionID, ancillaryData, requestTimestamp, rewardToken, reward, proposalBond);

        // Request a price from the OO
        _requestPrice(
            msg.sender,
            UmaConstants.YesOrNoIdentifier,
            requestTimestamp,
            ancillaryData,
            rewardToken,
            reward,
            proposalBond
        );

        emit QuestionUpdated(questionID, requestTimestamp, ancillaryData, rewardToken, reward, proposalBond);
    }

    /// @notice Flags a market for emergency resolution
    /// @param questionID - The unique questionID of the question
    function flagQuestionForEmergencyResolution(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), "Adapter/not-initialized");
        require(!isQuestionFlaggedForEmergencyResolution(questionID), "Adapter/already-flagged");

        questions[questionID].adminResolutionTimestamp = block.timestamp + emergencySafetyPeriod;
        emit QuestionFlaggedForAdminResolution(questionID);
    }

    /// @notice Allows an authorized user to report payouts in an emergency
    /// @param questionID - The unique questionID of the question
    /// @param payouts - Array of position payouts for the referenced question
    function emergencyReportPayouts(bytes32 questionID, uint256[] calldata payouts) external auth {
        require(isQuestionInitialized(questionID), "Adapter/not-initialized");
        require(isQuestionFlaggedForEmergencyResolution(questionID), "Adapter/not-flagged");
        require(block.timestamp > questions[questionID].adminResolutionTimestamp, "Adapter/safety-period-not-passed");
        require(payouts.length == 2, "Adapter/non-binary-payouts");

        QuestionData storage questionData = questions[questionID];

        questionData.resolved = true;
        ctf.reportPayouts(questionID, payouts);
        emit QuestionResolved(questionID, true);
    }

    /// @notice Allows an authorized user to pause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function pauseQuestion(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), "Adapter/not-initialized");
        QuestionData storage questionData = questions[questionID];

        questionData.paused = true;
        emit QuestionPaused(questionID);
    }

    /// @notice Allows an authorized user to unpause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function unPauseQuestion(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), "Adapter/not-initialized");
        QuestionData storage questionData = questions[questionID];
        questionData.paused = false;
        emit QuestionUnpaused(questionID);
    }

    /// @notice Utility function that verifies if a question is initialized
    /// @param questionID - The unique questionID
    function isQuestionInitialized(bytes32 questionID) public view returns (bool) {
        return questions[questionID].ancillaryData.length > 0;
    }

    /// @notice
    /// @param questionID - The unique questionID
    function isQuestionFlaggedForEmergencyResolution(bytes32 questionID) public view returns (bool) {
        return questions[questionID].adminResolutionTimestamp > 0;
    }
}
