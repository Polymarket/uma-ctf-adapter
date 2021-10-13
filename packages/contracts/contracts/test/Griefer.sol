// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import { UmaConditionalTokensBinaryAdapter } from "../UmaConditionalTokensBinaryAdapter.sol";

// Test contract to atomically settle and resolve a market
contract Griefer {
    UmaConditionalTokensBinaryAdapter public immutable target;

    constructor(address adapterAddress) {
        target = UmaConditionalTokensBinaryAdapter(adapterAddress);
    }

    function settleAndReport(bytes32 questionID) external {
        target.settle(questionID);
        target.reportPayouts(questionID);
    }
}
