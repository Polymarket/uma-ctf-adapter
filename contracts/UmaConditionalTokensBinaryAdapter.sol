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

    struct Question {
        bytes32 questionID;
        bytes question;
        uint256 minResolutionTimestamp;
    }

    mapping(bytes32 => Question) public questions;

    constructor(address conditionalTokenAddress, address optimisticOracleAddress){
        conditionalTokenContract = IConditionalTokens(conditionalTokenAddress);
        optimisticOracleContract = IOptimisticOracle(optimisticOracleAddress); 
    }
   
}
