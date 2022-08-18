// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { Auth } from "./mixins/Auth.sol";
import { BulletinBoard } from "./mixins/BulletinBoard.sol";

import { UmaConstants } from "./libraries/UmaConstants.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";

import { IUmaCtfAdapter } from "./interfaces/IUmaCtfAdapter.sol";
import { FinderInterface } from "./interfaces/FinderInterface.sol";
import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { SkinnyOptimisticRequester } from "./interfaces/SkinnyOptimisticRequester.sol";
import { AddressWhitelistInterface } from "./interfaces/AddressWhitelistInterface.sol";
import { OptimisticOracleV2Interface } from "./interfaces/OptimisticOracleV2Interface.sol";

/// @title UmaCtfAdapter
/// @notice Enables resolution of CTF markets via UMA's Optimistic Oracle
contract UmaCtfAdapter is IUmaCtfAdapter, Auth, BulletinBoard, SkinnyOptimisticRequester, ReentrancyGuard {
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
        /// @notice Additional bond required by Optimistic oracle proposers/disputers
        uint256 proposalBond;
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

    modifier onlyOptimisticOracle() {
        if (msg.sender != address(optimisticOracle)) revert NotOptimisticOracle();
        _;
    }

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
    /// @param ancillaryData - Data used to resolve a question
    /// @param rewardToken   - ERC20 token address used for payment of rewards and fees
    /// @param reward        - Reward offered to a successful proposer
    /// @param proposalBond  - Bond required to be posted by OO proposers/disputers. If 0, the default OO bond is used.
    function initializeQuestion(
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    ) external returns (bytes32 questionID) {
        if (!collateralWhitelist.isOnWhitelist(rewardToken)) revert UnsupportedToken();
        if (ancillaryData.length == 0 || ancillaryData.length > UmaConstants.AncillaryDataLimit)
            revert InvalidAncillaryData();

        questionID = getQuestionID(ancillaryData);

        if (_isInitialized(questions[questionID])) revert Initialized();
        
        uint256 requestTimestamp = block.timestamp;

        // Persist the question parameters in storage
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

    /// @notice Checks whether a questionID is ready to be resolved
    /// @param questionID - The unique questionID
    function readyToResolve(bytes32 questionID) public view returns (bool) {
        return _readyToResolve(questions[questionID]);
    }

    function _readyToResolve(QuestionData storage questionData) internal view returns (bool) {
        if (!_isInitialized(questionData)) {
            return false;
        }
        // Check that the OO has an available price
        return _hasPrice(questionData);
    }

    /// @notice Resolves a question
    /// Pulls price information from the OO and resolves the underlying CTF market.
    /// Is only available after price information is available on the OO
    /// @param questionID - The unique questionID of the question
    function resolve(bytes32 questionID) external {
        QuestionData storage questionData = questions[questionID];
        
        if (questionData.paused) revert Paused();
        if (questionData.resolved) revert Resolved();
        if (!_readyToResolve(questionData)) revert NotReadyToResolve();

        // Resolve the underlying market
        return _resolve(questionID, questionData);
    }

    /// @notice Retrieves the expected payout array of the question
    /// @param questionID - The unique questionID of the question
    function getExpectedPayouts(bytes32 questionID) public view returns (uint256[] memory) {
        QuestionData storage questionData = questions[questionID];
        
        if (!_isInitialized(questionData)) revert NotInitialized();
        if (!_hasPrice(questionData)) revert PriceNotAvailable();

        // Fetches price from OO
        int256 price = optimisticOracle
            .getRequest(
                address(this),
                UmaConstants.YesOrNoIdentifier,
                questionData.requestTimestamp,
                questionData.ancillaryData
            )
            .resolvedPrice;

        return _constructPayouts(price);
    }

    /// @notice OO callback which is executed when there is a dispute on an OO price request
    /// originating from the Adapter.
    /// Resets the question and sends out a new price request to the OO
    /// @param ancillaryData    - Ancillary data of the request
    function priceDisputed(
        bytes32,
        uint256,
        bytes memory ancillaryData,
        uint256
    ) external onlyOptimisticOracle {
        bytes32 questionID = getQuestionID(ancillaryData);
        QuestionData storage questionData = questions[questionID];

        // Upon dispute, immediately reset the question, sending out a new price request
        _reset(questionID, questionData);
    }

    /// @notice Checks if a question is initialized
    /// @param questionID - The unique questionID
    function isInitialized(bytes32 questionID) public view returns (bool) {
        return _isInitialized(questions[questionID]);
    }

    /// @notice Checks if a question has been flagged for emergency resolution
    /// @param questionID - The unique questionID
    function isFlagged(bytes32 questionID) public view returns (bool) {
        return _isFlagged(questions[questionID]);
    }

    function getQuestionID(bytes memory ancillaryData) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), ancillaryData));
    }

    /*////////////////////////////////////////////////////////////////////
                            AUTHORIZED FUNCTIONS 
    ///////////////////////////////////////////////////////////////////*/

    /// @notice Flags a market for emergency resolution
    /// @param questionID - The unique questionID of the question
    function flag(bytes32 questionID) external auth {
        QuestionData storage questionData = questions[questionID];
        
        if (!_isInitialized(questionData)) revert NotInitialized();
        if (_isFlagged(questionData)) revert Flagged();

        questionData.adminResolutionTimestamp = block.timestamp + emergencySafetyPeriod;
        
        // Flagging a question pauses it by default 
        questionData.paused = true;

        emit QuestionFlagged(questionID);
    }

    /// @notice Allows an authorized user to reset a question, sending out a new price request to the OO.
    /// Failsafe to be used if the priceDisputed callback reverts during execution.
    /// @param questionID - The unique questionID
    function reset(bytes32 questionID) external auth {
        QuestionData storage questionData = questions[questionID];
        if (!_isInitialized(questionData)) revert NotInitialized();
        if (questionData.resolved) revert Resolved();

        _reset(questionID, questionData);
    }

    /// @notice Allows an authorized user to resolve a CTF market in an emergency
    /// @param questionID   - The unique questionID of the question
    /// @param payouts      - Array of position payouts for the referenced question
    function emergencyResolve(bytes32 questionID, uint256[] calldata payouts) external auth {
        QuestionData storage questionData = questions[questionID];

        if (payouts.length != 2) revert InvalidPayouts();
        if (!_isInitialized(questionData)) revert NotInitialized();
        if (!_isFlagged(questionData)) revert NotFlagged();
        if (block.timestamp <= questionData.adminResolutionTimestamp) revert SafetyPeriodNotPassed();
        
        questionData.resolved = true;
        ctf.reportPayouts(questionID, payouts);
        emit QuestionEmergencyResolved(questionID, payouts);
    }

    /// @notice Allows an authorized user to pause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function pauseQuestion(bytes32 questionID) external auth {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        
        questionData.paused = true;
        emit QuestionPaused(questionID);
    }

    /// @notice Allows an authorized user to unpause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function unPauseQuestion(bytes32 questionID) external auth {
        QuestionData storage questionData = questions[questionID];
        if (!_isInitialized(questionData)) revert NotInitialized();
        
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
            adminResolutionTimestamp: 0
        });
    }

    /// @notice Request a price from the Optimistic Oracle
    /// Transfers reward token from the requestor if non-zero reward is specified
    /// @param requestor        - Address of the requestor
    /// @param requestTimestamp - Timestamp used in the OO request
    /// @param ancillaryData    - Data used to resolve a question
    /// @param rewardToken      - Address of the reward token
    /// @param reward           - Reward amount, denominated in rewardToken
    /// @param bond             - Bond amount used, denominated in rewardToken
    function _requestPrice(
        address requestor,
        uint256 requestTimestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond
    ) internal {
        // If non-zero reward, pay for the price request by transferring rewardToken from the requestor
        if (reward > 0) {
            // If requestor is the Adapter itself, pay for the request from the Adapter's balances
            if (requestor != address(this)) {
                TransferHelper.safeTransferFrom(rewardToken, requestor, address(this), reward);
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

        // Ensure that the dispute callback flag is set
        optimisticOracle.setCallbacks(
            UmaConstants.YesOrNoIdentifier,
            requestTimestamp,
            ancillaryData,
            false, // DO NOT set callback on priceProposed
            true, // DO set callback on priceDisputed
            false // DO NOT set callback on priceSettled
        );

        // Update the proposal bond on the Optimistic oracle if necessary
        if (bond > 0) {
            optimisticOracle.setBond(UmaConstants.YesOrNoIdentifier, requestTimestamp, ancillaryData, bond);
        }
    }

    /// @notice Reset the question by updating the requestTimestamp field and sending a new price request to the OO
    /// @param questionID - The unique questionID
    function _reset(bytes32 questionID, QuestionData storage questionData) internal {
        uint256 requestTimestamp = block.timestamp;

        // Update the question parameters in storage with a new request timestamp
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

    /// @notice Resolves the underlying CTF market
    /// @param questionID   - The unique questionID of the question
    /// @param questionData - The question data parameters
    function _resolve(bytes32 questionID, QuestionData storage questionData) internal {
        // Get the price from the OO
        int256 price = optimisticOracle.settleAndGetPrice(
            UmaConstants.YesOrNoIdentifier,
            questionData.requestTimestamp,
            questionData.ancillaryData
        );

        // Construct the payout array for the question
        uint256[] memory payouts = _constructPayouts(price);

        // Set resolved flag
        questionData.resolved = true;

        // Resolve the underlying CTF market
        ctf.reportPayouts(questionID, payouts);

        emit QuestionResolved(questionID, price, payouts);
    }

    function _hasPrice(QuestionData storage questionData) internal view returns (bool) {
        return
            optimisticOracle.hasPrice(
                address(this),
                UmaConstants.YesOrNoIdentifier,
                questionData.requestTimestamp,
                questionData.ancillaryData
            );
    }

    function _isFlagged(QuestionData storage questionData) internal view returns (bool) {
        return questionData.adminResolutionTimestamp > 0;
    }

    function _isInitialized(QuestionData storage questionData) internal view returns (bool) {
        return questionData.ancillaryData.length > 0;
    }

    /// @notice Construct the payout array given the price
    /// @param price - The price retrieved from the OO
    function _constructPayouts(int256 price) internal pure returns (uint256[] memory) {
        // Payouts: [YES, NO]
        uint256[] memory payouts = new uint256[](2);
        // Valid prices are 0, 0.5 and 1
        if (price != 0 && price != 0.5 ether && price != 1 ether) revert InvalidResolutionData();

        if (price == 0) {
            // NO: Report [Yes, No] as [0, 1]
            payouts[0] = 0;
            payouts[1] = 1;
        } else if (price == 0.5 ether) {
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

    /// @notice Prepares the question on the CTF
    /// @param questionID - The unique questionID
    function _prepareQuestion(bytes32 questionID) internal {
        ctf.prepareCondition(address(this), questionID, 2);
    }
}
