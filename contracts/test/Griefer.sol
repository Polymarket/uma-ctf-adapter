// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface AdapterInterface {
    function settle(bytes32 questionID) external;

    function reportPayouts(bytes32 questionID) external;
}

// Test contract to atomically settle and resolve a market
contract Griefer {
    AdapterInterface public immutable target;

    constructor(address adapterAddress) {
        target = AdapterInterface(adapterAddress);
    }

    function settleAndReport(bytes32 questionID) external {
        target.settle(questionID);
        target.reportPayouts(questionID);
    }
}
