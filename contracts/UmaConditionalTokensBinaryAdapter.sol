pragma solidity 0.7.5;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { IOptimisticOracle } from "./interfaces/IOptimisticOracle.sol";

/**
 *
 */
contract UmaConditionalTokensBinaryAdapter is Ownable {
    IConditionalTokens public immutable conditionalTokenContract;
    IOptimisticOracle public immutable optimisticOracleContract;

    // @notice Unique query identifier for the Optimistic Oracle
    bytes32 public constant identifier = bytes32("YES_OR_NO_QUERY");

    struct QuestionData {
        // @notice Unique ID of a condition
        bytes32 questionID;
        // @notice Data used to resolve a condition
        bytes ancillaryData;
        // @notice Unix timestamp at which a market can be resolved
        uint256 resolutionTime;
        // @notice ERC20 token address used for payment of rewards and fees
        address rewardToken;
        // @notice reward offered to a successful proposer
        uint256 reward;
        // @notice Flag marking whether resolution data has been requested from the Oracle
        bool resolutionDataRequested;
        // @notice Flag marking whether a condition is resolved
        bool resolved;
    }

    mapping(bytes32 => QuestionData) public questions;

    // @notice Emitted when a questionID is initialized
    event QuestionInitialized(
        bytes32 indexed questionID,
        bytes question,
        uint256 resolutionTime,
        address rewardToken,
        uint256 reward
    );

    // @notice Emitted when resolution data is requested from the Optimistic Oracle
    event ResolutionDataRequested(
        bytes32 indexed identifier,
        uint256 indexed timestamp,
        bytes32 indexed questionID,
        bytes ancillaryData
    );

    // @notice Emitted when a question is resolved
    event QuestionResolved(bytes32 indexed questionId, bool indexed emergencyReport);

    constructor(address conditionalTokenAddress, address optimisticOracleAddress) Ownable() {
        conditionalTokenContract = IConditionalTokens(conditionalTokenAddress);
        optimisticOracleContract = IOptimisticOracle(optimisticOracleAddress);
    }

    /**
     * @notice Initializes a question on the Adapter to report on. Once initialized, the resolution conditions may not be changed.
     *
     * @param questionID     - The unique questionID of condition
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
        require(!isQuestionInitialized(questionID), "Adapter::initializeQuestion: Question already initialized");
        questions[questionID] = QuestionData({
            questionID: questionID,
            ancillaryData: ancillaryData,
            resolutionTime: resolutionTime,
            rewardToken: rewardToken,
            reward: reward,
            resolutionDataRequested: false,
            resolved: false
        });
        emit QuestionInitialized(questionID, ancillaryData, resolutionTime, rewardToken, reward);
    }

    /**
     * @notice - Checks whether or not a question can start the resolution process
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
     * @notice - Requests resolution data from the Optimistic Oracle
     */
    function requestResolutionData(bytes32 questionID) public returns (uint256) {
        require(
            readyToRequestResolution(questionID),
            "Adapter::requestResolutionData: Question not ready to be resolved"
        );
        QuestionData storage questionData = questions[questionID];
        optimisticOracleContract.requestPrice(
            identifier,
            questionData.resolutionTime,
            questionData.ancillaryData,
            IERC20(questionData.rewardToken),
            questionData.reward
        );
        questionData.resolutionDataRequested = true;
        emit ResolutionDataRequested(identifier, questionData.resolutionTime, questionID, questionData.ancillaryData);
    }

    /**
     * @notice - Checks whether a questionID is ready to report payouts
     */
    function readyToReportPayouts(bytes32 questionID) public view returns (bool) {
        if (!isQuestionInitialized(questionID)) {
            return false;
        }
        QuestionData storage questionData = questions[questionID];
        if (questionData.resolutionDataRequested == false) {
            return false;
        }
        if (questionData.resolved == true) {
            return false;
        }

        return
            optimisticOracleContract.hasPrice(
                address(this),
                identifier,
                questionData.resolutionTime,
                questionData.ancillaryData
            );
    }

    function reportPayouts(bytes32 questionID) public {
        require(readyToReportPayouts(questionID), "Adapter::reportPayouts: questionID not ready to report payouts");
        QuestionData storage questionData = questions[questionID];

        // fetches resolution data,
        uint256 resolutionData = uint256(
            optimisticOracleContract.settleAndGetPrice(
                identifier,
                questionData.resolutionTime,
                questionData.ancillaryData
            )
        );

        // Payouts: [YES, NO]
        uint256[] memory payouts = new uint256[](2);
        require(resolutionData == 0 || resolutionData == 1, "Adapter::reportPayouts: Invalid resolution data");

        if (resolutionData == 0) {
            //NO: Set payouts to [0, 1]
            payouts[0] = 0;
            payouts[1] = 1;
        } else {
            // YES: Set payouts to [1, 0]
            payouts[0] = 1;
            payouts[1] = 0;
        }

        conditionalTokenContract.reportPayouts(questionID, payouts);
        questionData.resolved = true;
        emit QuestionResolved(questionID, false);
    }

    function emergencyReportPayouts(bytes32 questionID, uint256[] calldata payouts) external onlyOwner {
        // allows the adapter owner to resolve payouts in emergency situations
    }

    function isQuestionInitialized(bytes32 questionID) internal view returns (bool) {
        return questions[questionID].resolutionTime != 0;
    }
}
