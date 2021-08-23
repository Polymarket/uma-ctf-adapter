pragma solidity 0.7.5;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { IConditionalTokens } from "./interfaces/IConditionalTokens.sol";
import { IOptimisticOracle } from "./interfaces/IOptimisticOracle.sol";

/**
 *
 */
contract UmaConditionalTokensBinaryAdapter is Ownable {
    IConditionalTokens public immutable conditionalTokenContract;
    IOptimisticOracle public immutable optimisticOracleContract;

    bytes public constant oracleQueryIdentifier = bytes("YES_OR_NO_QUERY");

    struct QuestionData {
        bytes32 questionID;
        bytes ancillaryData;
        uint256 resolutionTime;
    }

    mapping(bytes32 => QuestionData) public questions;

    // Events
    event QuestionInitialized(bytes32 indexed questionID, bytes question, uint256 resolutionTime);
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

    function initializeQuestion(
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 resolutionTime
    ) public onlyOwner {
        require(questions[questionID].resolutionTime == 0, "Question already initialized");
        questions[questionID] = QuestionData({
            questionID: questionID,
            ancillaryData: ancillaryData,
            resolutionTime: resolutionTime
        });

        emit QuestionInitialized(questionID, ancillaryData, resolutionTime);
    }

    function readyToRequestResolution(bytes32 questionID) public view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp > (questions[questionID].resolutionTime + 2 hours);
    }

    function requestResolutionData(bytes32 questionID) public {
        // requests resolution data from the optimistic oracle, calls `optimisticOracle.requestPrice`
        // require(readyToRequestResolution(questionID));
    }

    function readyToReportPayouts(bytes32 questionID) public view returns (bool) {
        // a function that calls `optimisticOracle.hasPrice` to verify that the OO has price data
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
