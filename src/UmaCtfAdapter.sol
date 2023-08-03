// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import { Auth } from "./mixins/Auth.sol";
import { BulletinBoard } from "./mixins/BulletinBoard.sol";

import { TransferHelper } from "./libraries/TransferHelper.sol";
import { AncillaryDataLib } from "./libraries/AncillaryDataLib.sol";

import { IFinder } from "./interfaces/IFinder.sol";
import { IAddressWhitelist } from "./interfaces/IAddressWhitelist.sol";
import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { IOptimisticOracleV2 } from "./interfaces/IOptimisticOracleV2.sol";
import { IOptimisticRequester } from "./interfaces/IOptimisticRequester.sol";

import { QuestionData, IUmaCtfAdapter } from "./interfaces/IUmaCtfAdapter.sol";

/// @title UmaCtfAdapter
/// @notice Enables resolution of Polymarket CTF markets via UMA's Optimistic Oracle
contract UmaCtfAdapter is IUmaCtfAdapter, Auth, BulletinBoard, IOptimisticRequester, ReentrancyGuard {
    /*///////////////////////////////////////////////////////////////////
                            IMMUTABLES 
    //////////////////////////////////////////////////////////////////*/

    /// @notice Conditional Tokens Framework
    IConditionalTokens public immutable ctf;

    /// @notice Optimistic Oracle
    IOptimisticOracleV2 public immutable optimisticOracle;

    /// @notice Collateral Whitelist
    IAddressWhitelist public immutable collateralWhitelist;

    /// @notice Time period after which an admin can emergency resolve a condition
    uint256 public constant EMERGENCY_SAFETY_PERIOD = 2 days;

    /// @notice Unique query identifier for the Optimistic Oracle
    /// From UMIP-107
    bytes32 public constant YES_OR_NO_IDENTIFIER = "YES_OR_NO_QUERY";

    /// @notice Maximum ancillary data length
    /// From OOV2 function OO_ANCILLARY_DATA_LIMIT
    uint256 public constant MAX_ANCILLARY_DATA = 8139;

    /// @notice Mapping of questionID to QuestionData
    mapping(bytes32 => QuestionData) public questions;

    modifier onlyOptimisticOracle() {
        if (msg.sender != address(optimisticOracle)) revert NotOptimisticOracle();
        _;
    }

    constructor(address _ctf, address _finder) {
        ctf = IConditionalTokens(_ctf);
        IFinder finder = IFinder(_finder);
        optimisticOracle = IOptimisticOracleV2(finder.getImplementationAddress("OptimisticOracleV2"));
        collateralWhitelist = IAddressWhitelist(finder.getImplementationAddress("CollateralWhitelist"));
    }

    /*///////////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS 
    //////////////////////////////////////////////////////////////////*/

    /// @notice Initializes a question
    /// Atomically adds the question to the Adapter, prepares it on the ConditionalTokens Framework and requests a price from the OO.
    /// If a reward is provided, the caller must have approved the Adapter as spender and have enough rewardToken
    /// to pay for the price request.
    /// Prepares the condition using the Adapter as the oracle and a fixed outcome slot count = 2.
    /// @param ancillaryData - Data used to resolve a question
    /// @param rewardToken   - ERC20 token address used for payment of rewards and fees
    /// @param reward        - Reward offered to a successful proposer
    /// @param proposalBond  - Bond required to be posted by OO proposers/disputers. If 0, the default OO bond is used.
    /// @param liveness      - UMA liveness period in seconds. If 0, the default liveness period is used.
    function initialize(
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        uint256 liveness
    ) external returns (bytes32 questionID) {
        if (!collateralWhitelist.isOnWhitelist(rewardToken)) revert UnsupportedToken();

        bytes memory data = AncillaryDataLib._appendAncillaryData(msg.sender, ancillaryData);
        if (ancillaryData.length == 0 || data.length > MAX_ANCILLARY_DATA) revert InvalidAncillaryData();

        questionID = keccak256(data);

        if (_isInitialized(questions[questionID])) revert Initialized();

        uint256 timestamp = block.timestamp;

        // Persist the question parameters in storage
        _saveQuestion(msg.sender, questionID, data, timestamp, rewardToken, reward, proposalBond, liveness);

        // Prepare the question on the CTF
        ctf.prepareCondition(address(this), questionID, 2);

        // Request a price for the question from the OO
        _requestPrice(msg.sender, timestamp, data, rewardToken, reward, proposalBond, liveness);

        emit QuestionInitialized(questionID, timestamp, msg.sender, data, rewardToken, reward, proposalBond);
    }

    /// @notice Checks whether a questionID is ready to be resolved
    /// @param questionID - The unique questionID
    function ready(bytes32 questionID) public view returns (bool) {
        return _ready(questions[questionID]);
    }

    /// @notice Resolves a question
    /// Pulls price information from the OO and resolves the underlying CTF market.
    /// Reverts if price is not available on the OO
    /// Resets the question if the price returned by the OO is the Ignore price
    /// @param questionID - The unique questionID of the question
    function resolve(bytes32 questionID) external {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (questionData.paused) revert Paused();
        if (questionData.resolved) revert Resolved();
        if (!_hasPrice(questionData)) revert NotReadyToResolve();

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
        int256 price = optimisticOracle.getRequest(
            address(this), YES_OR_NO_IDENTIFIER, questionData.requestTimestamp, questionData.ancillaryData
        ).resolvedPrice;

        return _constructPayouts(price);
    }

    /// @notice Callback which is executed on dispute
    /// Resets the question and sends out a new price request to the OO
    /// @param ancillaryData    - Ancillary data of the request
    function priceDisputed(bytes32, uint256, bytes memory ancillaryData, uint256) external onlyOptimisticOracle {
        bytes32 questionID = keccak256(ancillaryData);
        QuestionData storage questionData = questions[questionID];

        if (questionData.reset) return;

        // If the question has not been reset previously, reset the question
        // Ensures that there are at most 2 OO Requests at a time for a question
        _reset(address(this), questionID, questionData);
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

    /// @notice Gets the QuestionData for the given questionID
    /// @param questionID - The unique questionID
    function getQuestion(bytes32 questionID) external view returns (QuestionData memory) {
        return questions[questionID];
    }

    /*////////////////////////////////////////////////////////////////////
                            ADMIN ONLY FUNCTIONS 
    ///////////////////////////////////////////////////////////////////*/

    /// @notice Flags a market for emergency resolution
    /// @param questionID - The unique questionID of the question
    function flag(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (_isFlagged(questionData)) revert Flagged();
        if (questionData.resolved) revert Resolved();

        questionData.emergencyResolutionTimestamp = block.timestamp + EMERGENCY_SAFETY_PERIOD;
        questionData.paused = true;

        emit QuestionFlagged(questionID);
    }

    /// @notice Unflags a market for emergency resolution
    /// @param questionID - The unique questionID of the question
    function unflag(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (!_isFlagged(questionData)) revert NotFlagged();
        if (questionData.resolved) revert Resolved();
        if (block.timestamp > questionData.emergencyResolutionTimestamp) revert SafetyPeriodPassed();

        questionData.emergencyResolutionTimestamp = 0;
        questionData.paused = false;

        emit QuestionUnflagged(questionID);
    }

    /// @notice Allows an admin to reset a question, sending out a new price request to the OO.
    /// Failsafe to be used if the priceDisputed callback reverts during execution.
    /// @param questionID - The unique questionID
    function reset(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];
        if (!_isInitialized(questionData)) revert NotInitialized();
        if (questionData.resolved) revert Resolved();

        // Reset the question, paying for the price request from the caller
        _reset(msg.sender, questionID, questionData);
    }

    /// @notice Allows an admin to resolve a CTF market in an emergency
    /// @param questionID   - The unique questionID of the question
    /// @param payouts      - Array of position payouts for the referenced question
    function emergencyResolve(bytes32 questionID, uint256[] calldata payouts) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (payouts.length != 2) revert InvalidPayouts();
        if (!_isInitialized(questionData)) revert NotInitialized();
        if (!_isFlagged(questionData)) revert NotFlagged();
        if (block.timestamp < questionData.emergencyResolutionTimestamp) revert SafetyPeriodNotPassed();

        questionData.resolved = true;
        ctf.reportPayouts(questionID, payouts);
        emit QuestionEmergencyResolved(questionID, payouts);
    }

    /// @notice Allows an admin to pause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function pause(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (questionData.resolved) revert Resolved();

        questionData.paused = true;
        emit QuestionPaused(questionID);
    }

    /// @notice Allows an admin to unpause market resolution in an emergency
    /// @param questionID - The unique questionID of the question
    function unpause(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];
        if (!_isInitialized(questionData)) revert NotInitialized();

        questionData.paused = false;
        emit QuestionUnpaused(questionID);
    }

    /*///////////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS 
    //////////////////////////////////////////////////////////////////*/

    function _ready(QuestionData storage questionData) internal view returns (bool) {
        if (!_isInitialized(questionData)) return false;
        if (questionData.paused) return false;
        if (questionData.resolved) return false;
        return _hasPrice(questionData);
    }

    function _saveQuestion(
        address creator,
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 requestTimestamp,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        uint256 liveness
    ) internal {
        questions[questionID] = QuestionData({
            requestTimestamp: requestTimestamp,
            reward: reward,
            proposalBond: proposalBond,
            liveness: liveness,
            emergencyResolutionTimestamp: 0,
            resolved: false,
            paused: false,
            reset: false,
            rewardToken: rewardToken,
            creator: creator,
            ancillaryData: ancillaryData
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
    /// @param liveness         - UMA liveness period, will be the default liveness period if 0.
    function _requestPrice(
        address requestor,
        uint256 requestTimestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond,
        uint256 liveness
    ) internal {
        if (reward > 0) {
            // If the requestor is not the Adapter, the requestor pays for the price request
            // If not, the Adapter pays for the price request
            if (requestor != address(this)) {
                TransferHelper._transferFromERC20(rewardToken, requestor, address(this), reward);
            }

            // Approve the OO as spender on the reward token from the Adapter
            if (IERC20(rewardToken).allowance(address(this), address(optimisticOracle)) < reward) {
                IERC20(rewardToken).approve(address(optimisticOracle), type(uint256).max);
            }
        }

        // Send a price request to the Optimistic oracle
        optimisticOracle.requestPrice(
            YES_OR_NO_IDENTIFIER, requestTimestamp, ancillaryData, IERC20(rewardToken), reward
        );

        // Ensure the price request is event based
        optimisticOracle.setEventBased(YES_OR_NO_IDENTIFIER, requestTimestamp, ancillaryData);

        // Ensure that the dispute callback flag is set
        optimisticOracle.setCallbacks(
            YES_OR_NO_IDENTIFIER,
            requestTimestamp,
            ancillaryData,
            false, // DO NOT set callback on priceProposed
            true, // DO set callback on priceDisputed
            false // DO NOT set callback on priceSettled
        );

        // Update the proposal bond on the Optimistic oracle if necessary
        if (bond > 0) optimisticOracle.setBond(YES_OR_NO_IDENTIFIER, requestTimestamp, ancillaryData, bond);
        if (liveness > 0) {
            optimisticOracle.setCustomLiveness(YES_OR_NO_IDENTIFIER, requestTimestamp, ancillaryData, liveness);
        }
    }

    /// @notice Reset the question by updating the requestTimestamp field and sending a new price request to the OO
    /// @param questionID - The unique questionID
    function _reset(address requestor, bytes32 questionID, QuestionData storage questionData) internal {
        uint256 requestTimestamp = block.timestamp;
        // Update the question parameters in storage
        questionData.requestTimestamp = requestTimestamp;
        questionData.reset = true;

        // Send out a new price request with the new timestamp
        _requestPrice(
            requestor,
            requestTimestamp,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond,
            questionData.liveness
        );

        emit QuestionReset(questionID);
    }

    /// @notice Resolves the underlying CTF market
    /// @param questionID   - The unique questionID of the question
    /// @param questionData - The question data parameters
    function _resolve(bytes32 questionID, QuestionData storage questionData) internal {
        // Get the price from the OO
        int256 price = optimisticOracle.settleAndGetPrice(
            YES_OR_NO_IDENTIFIER, questionData.requestTimestamp, questionData.ancillaryData
        );

        // If the OO returns the ignore price, reset the question
        if (price == _ignorePrice()) return _reset(address(this), questionID, questionData);

        // Construct the payout array for the question
        uint256[] memory payouts = _constructPayouts(price);

        // Set resolved flag
        questionData.resolved = true;

        // Resolve the underlying CTF market
        ctf.reportPayouts(questionID, payouts);

        emit QuestionResolved(questionID, price, payouts);
    }

    function _hasPrice(QuestionData storage questionData) internal view returns (bool) {
        return optimisticOracle.hasPrice(
            address(this), YES_OR_NO_IDENTIFIER, questionData.requestTimestamp, questionData.ancillaryData
        );
    }

    function _isFlagged(QuestionData storage questionData) internal view returns (bool) {
        return questionData.emergencyResolutionTimestamp > 0;
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
        if (price != 0 && price != 0.5 ether && price != 1 ether) revert InvalidOOPrice();

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

    function _ignorePrice() internal pure returns (int256) {
        return type(int256).min;
    }
}
