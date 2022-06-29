// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { Auth } from "./mixins/Auth.sol";
import { BulletinBoard } from "./mixins/BulletinBoard.sol";

import { UmaConstants } from "./libraries/UmaConstants.sol";
import { AdapterErrors } from "./libraries/AdapterErrors.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";

import { FinderInterface } from "./interfaces/FinderInterface.sol";
import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { AddressWhitelistInterface } from "./interfaces/AddressWhitelistInterface.sol";
import { OptimisticOracleV2Interface } from "./interfaces/OptimisticOracleV2Interface.sol";

/// @title UmaCtfAdapter
/// @notice Enables resolution of CTF markets via UMA's Optimistic Oracle
contract UmaCtfAdapter is Auth, BulletinBoard, ReentrancyGuard {
    /*///////////////////////////////////////////////////////////////////
                            IMMUTABLES 
    //////////////////////////////////////////////////////////////////*/

    /// @notice Conditional Tokens Framework
    IConditionalTokens public immutable ctf;

    /// @notice Optimistic Oracle
    OptimisticOracleV2Interface public immutable optimisticOracle;

    /// @notice Collateral Whitelist
    AddressWhitelistInterface public immutable collateralWhitelist;

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
        /// @notice The address of the question creator
        address creator;
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
    event QuestionFlaggedForAdminResolution(bytes32 indexed questionID);

    /// @notice Emitted when a question is reset
    event QuestionReset(bytes32 indexed questionID);

    /// @notice Emitted when a question is settled
    event QuestionSettled(bytes32 indexed questionID, int256 indexed settledPrice);

    /// @notice Emitted when a question is resolved
    event QuestionResolved(bytes32 indexed questionID, bool indexed emergencyReport, uint256[] payouts);

    /// @notice Emitted when tokens are withdrawn from the Adapter
    event TokensWithdrawn(address token, address to, uint256 value);

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
    /// If a reward is provided, the caller must have approved the Adapter as spender and have enough rewardToken
    /// to pay for the price request.
    /// Prepares the condition using the Adapter as the oracle and a fixed outcome slot count = 2.
    /// @param questionID    - The unique questionID of the question
    /// @param ancillaryData - Data used to resolve a question
    /// @param rewardToken   - ERC20 token address used for payment of rewards and fees
    /// @param reward        - Reward offered to a successful proposer
    /// @param proposalBond  - Bond required to be posted by OO proposers/disputers. If 0, the default OO bond is used.
    function initializeQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    ) external nonReentrant {
        require(!isQuestionInitialized(questionID), AdapterErrors.AlreadyInitialized);
        require(collateralWhitelist.isOnWhitelist(rewardToken), AdapterErrors.UnsupportedToken);
        require(
            ancillaryData.length > 0 && ancillaryData.length <= UmaConstants.AncillaryDataLimit,
            AdapterErrors.InvalidAncillaryData
        );

        uint256 requestTimestamp = block.timestamp;

        // Save the question parameters in storage
        _saveQuestion(msg.sender, questionID, ancillaryData, requestTimestamp, rewardToken, reward, proposalBond);

        // Prepare the question on the CTF
        _prepareQuestion(questionID);

        // Request a price for the question from the OO
        _requestPrice(msg.sender, requestTimestamp, ancillaryData, rewardToken, reward, proposalBond);

        emit QuestionInitialized(
            questionID,
            requestTimestamp,
            msg.sender,
            ancillaryData,
            rewardToken,
            reward,
            proposalBond
        );
    }

    /// @notice Checks whether a questionID is ready to be settled
    /// @param questionID - The unique questionID of the question
    function readyToSettle(bytes32 questionID) public view returns (bool) {
        if (!isQuestionInitialized(questionID)) {
            return false;
        }

        QuestionData storage questionData = questions[questionID];

        // Ensure question has not been resolved
        if (questionData.resolved) {
            return false;
        }

        // Ensure question has not been settled
        if (questionData.settled != 0) {
            return false;
        }

        // If the question is disputed by the DVM, do not wait for DVM resolution
        // instead, immediately flag the question as ready to be settled
        if (_isDisputed(questionData)) {
            return true;
        }

        // Check that the OO has an available price
        return
            optimisticOracle.hasPrice(
                address(this),
                UmaConstants.YesOrNoIdentifier,
                questionData.requestTimestamp,
                questionData.ancillaryData
            );
    }

    /// @notice Settle the question
    /// Settling a question means that:
    /// 1. There is an undisputed price available from the OO and so the question can move on to resolution
    /// 2. The question has been disputed, and a new price request needs to be sent out for the question
    /// @param questionID - The unique questionID of the question
    function settle(bytes32 questionID) external nonReentrant {
        require(readyToSettle(questionID), AdapterErrors.NotReadyToSettle);

        QuestionData storage questionData = questions[questionID];
        require(!questionData.paused, AdapterErrors.Paused);

        // If the question is disputed, reset the question
        if (_isDisputed(questionData)) {
            return _reset(questionID, questionData);
        }

        return _settle(questionID, questionData);
    }

    /// @notice Retrieves the expected payout of a settled question
    /// @param questionID - The unique questionID of the question
    function getExpectedPayouts(bytes32 questionID) public view returns (uint256[] memory) {
        require(isQuestionInitialized(questionID), AdapterErrors.NotInitialized);
        QuestionData storage questionData = questions[questionID];

        require(questionData.settled > 0, AdapterErrors.NotSettled);
        require(!questionData.paused, AdapterErrors.Paused);

        // Fetches resolution data from OO
        int256 resolutionData = _getResolutionData(questionData);

        // Payouts: [YES, NO]
        uint256[] memory payouts = new uint256[](2);

        // Valid prices are 0, 0.5 and 1
        require(
            resolutionData == 0 || resolutionData == 0.5 ether || resolutionData == 1 ether,
            AdapterErrors.InvalidData
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

        require(!questionData.resolved, AdapterErrors.AlreadyResolved);
        require(block.number > questionData.settled, AdapterErrors.SameBlockSettleReport);

        // Payouts: [YES, NO]
        // getExpectedPayouts verifies that questionID is settled and can be resolved
        uint256[] memory payouts = getExpectedPayouts(questionID);

        questionData.resolved = true;
        ctf.reportPayouts(questionID, payouts);
        emit QuestionResolved(questionID, false, payouts);
    }

    /// @notice Checks if a question is initialized
    /// @param questionID - The unique questionID
    function isQuestionInitialized(bytes32 questionID) public view returns (bool) {
        return questions[questionID].ancillaryData.length > 0;
    }

    /// @notice Checks if a question has been flagged for emergency resolution
    /// @param questionID - The unique questionID
    function isQuestionFlaggedForEmergencyResolution(bytes32 questionID) public view returns (bool) {
        return questions[questionID].adminResolutionTimestamp > 0;
    }

    /*////////////////////////////////////////////////////////////////////
                            AUTHORIZED FUNCTIONS 
    ///////////////////////////////////////////////////////////////////*/

    /// @notice Flags a market for emergency resolution
    /// @param questionID - The unique questionID of the question
    function flagQuestionForEmergencyResolution(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), AdapterErrors.NotInitialized);
        require(!isQuestionFlaggedForEmergencyResolution(questionID), AdapterErrors.AlreadyFlagged);

        questions[questionID].adminResolutionTimestamp = block.timestamp + emergencySafetyPeriod;
        emit QuestionFlaggedForAdminResolution(questionID);
    }

    /// @notice Allows an authorized user to report payouts in an emergency
    /// @param questionID - The unique questionID of the question
    /// @param payouts - Array of position payouts for the referenced question
    function emergencyReportPayouts(bytes32 questionID, uint256[] calldata payouts) external auth {
        require(isQuestionInitialized(questionID), AdapterErrors.NotInitialized);
        require(isQuestionFlaggedForEmergencyResolution(questionID), AdapterErrors.NotFlagged);
        require(block.timestamp > questions[questionID].adminResolutionTimestamp, AdapterErrors.SafetyPeriodNotPassed);
        require(payouts.length == 2, AdapterErrors.NonBinaryPayouts);

        QuestionData storage questionData = questions[questionID];

        questionData.resolved = true;
        ctf.reportPayouts(questionID, payouts);
        emit QuestionResolved(questionID, true, payouts);
    }

    /// @notice Allows an authorized user to pause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function pauseQuestion(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), AdapterErrors.NotInitialized);
        QuestionData storage questionData = questions[questionID];

        questionData.paused = true;
        emit QuestionPaused(questionID);
    }

    /// @notice Allows an authorized user to unpause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function unPauseQuestion(bytes32 questionID) external auth {
        require(isQuestionInitialized(questionID), AdapterErrors.NotInitialized);
        QuestionData storage questionData = questions[questionID];
        questionData.paused = false;
        emit QuestionUnpaused(questionID);
    }

    /*///////////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS 
    //////////////////////////////////////////////////////////////////*/

    function _saveQuestion(
        address creator,
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 requestTimestamp,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    ) internal {
        questions[questionID] = QuestionData({
            creator: creator,
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
    /// @param requestTimestamp - Timestamp used in the OO request
    /// @param ancillaryData    - Data used to resolve a question
    /// @param rewardToken      - Address of the reward token
    /// @param reward           - Reward amount, denominated in rewardToken
    /// @param bond             - Bond amount used, denominated in rewardToken
    function _requestPrice(
        address caller,
        uint256 requestTimestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond
    ) internal {
        // If non-zero reward, pay for the price request by transferring rewardToken from the caller
        if (reward > 0) {
            if (caller != address(this)) {
                // If caller is the Adapter itself, do not transfer the reward. Pay for the request from the Adapter's balances
                TransferHelper.safeTransferFrom(rewardToken, caller, address(this), reward);
            }

            // Approve the OO as spender on the reward token from the Adapter
            if (IERC20(rewardToken).allowance(address(this), address(optimisticOracle)) < reward) {
                TransferHelper.safeApprove(rewardToken, address(optimisticOracle), type(uint256).max);
            }
        }

        // Send a price request to the Optimistic oracle
        optimisticOracle.requestPrice(
            UmaConstants.YesOrNoIdentifier,
            requestTimestamp,
            ancillaryData,
            IERC20(rewardToken),
            reward
        );

        // Ensure the price request is event based
        optimisticOracle.setEventBased(UmaConstants.YesOrNoIdentifier, requestTimestamp, ancillaryData);

        // Update the proposal bond on the Optimistic oracle if necessary
        if (bond > 0) {
            optimisticOracle.setBond(UmaConstants.YesOrNoIdentifier, requestTimestamp, ancillaryData, bond);
        }
    }

    /// @notice Settles the question
    /// @param questionID   - The unique questionID
    /// @param questionData - The question parameters
    function _settle(bytes32 questionID, QuestionData storage questionData) internal {
        // Get the price from the OO
        int256 price = optimisticOracle.settleAndGetPrice(
            UmaConstants.YesOrNoIdentifier,
            questionData.requestTimestamp,
            questionData.ancillaryData
        );

        // Set the settled block number
        questionData.settled = block.number;

        emit QuestionSettled(questionID, price);
    }

    /// @notice Checks if the request of a question is disputed
    /// @param questionData - The question parameters
    function _isDisputed(QuestionData storage questionData) internal view returns (bool) {
        return
            optimisticOracle
                .getRequest(
                    address(this),
                    UmaConstants.YesOrNoIdentifier,
                    questionData.requestTimestamp,
                    questionData.ancillaryData
                )
                .disputer != address(0);
    }

    /// @notice Reset the question by updating the requestTimestamp field and sending out a new price request to the OO
    /// @param questionID - The unique questionID
    function _reset(bytes32 questionID, QuestionData storage questionData) internal {
        uint256 requestTimestamp = block.timestamp;

        // Update the question parameters in storage with the new request timestamp
        _saveQuestion(
            questionData.creator,
            questionID,
            questionData.ancillaryData,
            requestTimestamp,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond
        );

        // Send out a new price request with the new request timestamp
        _requestPrice(
            address(this),
            requestTimestamp,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond
        );

        emit QuestionReset(questionID);
    }

    /// @notice Gets resolution data for the question from the OO
    /// @param questionData - The parameters of the question
    function _getResolutionData(QuestionData storage questionData) internal view returns (int256) {
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

    /// @notice Prepares the question on the CTF
    /// @param questionID - The unique questionID
    function _prepareQuestion(bytes32 questionID) internal {
        ctf.prepareCondition(address(this), questionID, 2);
    }
}
