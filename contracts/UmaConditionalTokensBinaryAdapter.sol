pragma solidity 0.7.5;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { IOptimisticOracle } from "./interfaces/IOptimisticOracle.sol";

/**
 *
 */
contract UmaConditionalTokensBinaryAdapter is Ownable {
    IConditionalTokens public immutable conditionalTokenContract;
    IOptimisticOracle public immutable optimisticOracleContract;

    bytes32 public constant oracleQueryIdentifier = bytes32("YES_OR_NO_QUERY");

    struct QuestionData {
        bytes32 questionID;
        bytes ancillaryData;
        uint256 resolutionTime;
        address rewardToken;
        uint256 reward;
    }

    mapping(bytes32 => QuestionData) public questions;
    mapping(bytes32 => bool) public resolutionDataRequests;

    // Events
    event QuestionInitialized(
        bytes32 indexed questionID,
        bytes question,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward
    );

    event QuestionResolved(bytes32 indexed questionId, bool indexed emergencyReport);

    event ResolutionDataRequested(
        address indexed identifier,
        uint256 indexed timestamp,
        bytes32 indexed questionID,
        bytes ancillaryData
    );

    constructor(address conditionalTokenAddress, address optimisticOracleAddress) Ownable() {
        conditionalTokenContract = IConditionalTokens(conditionalTokenAddress);
        optimisticOracleContract = IOptimisticOracle(optimisticOracleAddress);
    }

    /**
     * @notice Initializes a question on the Adapter to report on. Once initialized, the resolution conditions may not be changed.
     * @dev Only the owner can call initializeQuestion
     *
     * @param questionID     - The questionID of condition
     * @param ancillaryData  - Holds data used to resolve a question
     * @param resolutionTime - timestamp at which the Adapter can resolve a question
     * @param rewardToken    - ERC20 token address used for payment of rewards and fees
     * @param reward         - reward offered to a successful proposer
     */
    function initializeQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward
    ) public onlyOwner {
        require(questions[questionID].resolutionTime == 0, "Adapter::initializeQuestion: Question already initialized");
        questions[questionID] = QuestionData(questionID, ancillaryData, resolutionTime, rewardToken, reward);
        emit QuestionInitialized(questionID, ancillaryData, resolutionTime, rewardToken, reward);
    }

    /**
     * @notice - Checks whether or not a question can start the resolution process
     */
    function readyToRequestResolution(bytes32 questionID) public view returns (bool) {
        if (questions[questionID].resolutionTime == 0) {
            return false;
        }
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp > questions[questionID].resolutionTime;
    }

    /**
     * @notice - Requests question resolution data from the Optimistic Oracle
     */
    function requestResolutionData(bytes32 questionID) public returns (uint256) {
        require(
            readyToRequestResolution(questionID),
            "Adapter::requestResolutionData: Question not ready to be resolved"
        );
        require(
            resolutionDataRequests[questionID] == false,
            "Adapter::requestResolutionData: ResolutionData already requested"
        );
        QuestionData storage questionData = questions[questionID];
        optimisticOracleContract.requestPrice(
            oracleQueryIdentifier,
            questionData.resolutionTime,
            questionData.ancillaryData,
            IERC20(questionData.rewardToken),
            questionData.reward
        );
        resolutionDataRequests[questionID] = true;
    }

    function readyToReportPayouts(bytes32 questionID) public view returns (bool) {
        QuestionData storage questionData = questions[questionID];
        if (questionData.resolutionTime == 0) {
            return false;
        }
        return
            optimisticOracleContract.hasPrice(
                address(this),
                oracleQueryIdentifier,
                questionData.resolutionTime,
                questionData.ancillaryData
            );
    }

    function reportPayouts(bytes32 questionID) public {
        // require(readyToReportPayouts(questionID))
        // calls `optimisticOracle.settleAndGetPrice`
        // fetches resolution data, constructs outcomeIndex array and calls conditionalTokens.reportPayouts
    }

    function emergencyReportPayouts(bytes32 questionId, uint256[] calldata payouts) external onlyOwner {
        // allows the adapter owner to resolve payouts in emergency situations
    }
}
