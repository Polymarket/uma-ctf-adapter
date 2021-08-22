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

    struct QuestionData {
        bytes32 questionID;
        bytes question;
        uint256 resolutionTime;
    }

    mapping(bytes32 => QuestionData) public questions;


    // Events
    event QuestionInitialized(bytes32 indexed questionID, bytes question, uint256 resolutionTime);
    event QuestionResolved(bytes32 indexed questionId, bool indexed emergencyReport);
    event ResolutionDataRequested(address indexed identifier, uint256 indexed timestamp, 
                                  bytes32 indexed questionID, bytes ancillaryData);


    constructor(address conditionalTokenAddress, address optimisticOracleAddress) Ownable() {
        conditionalTokenContract = IConditionalTokens(conditionalTokenAddress);
        optimisticOracleContract = IOptimisticOracle(optimisticOracleAddress); 
    }

    function initializeQuestion(bytes32 questionID, bytes memory question, uint256 resolutionTime) public onlyOwner {
        require(questions[questionID].resolutionTime == 0, "Question already initialized");
        questions[questionID] = QuestionData({
            questionID: questionID,
            question: question,
            resolutionTime: resolutionTime
        });

        emit QuestionInitialized(questionID, question, resolutionTime);
    }

    function readyToReport(bytes32 questionID) public view returns (bool) {
        return block.timestamp > (questions[questionID].resolutionTime + 2 hours);
    }

   
}
