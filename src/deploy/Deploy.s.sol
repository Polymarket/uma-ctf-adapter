// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { UmaCtfAdapter } from "src/UmaCtfAdapter.sol";

/// @title Deploy
/// @notice Script to deploy the UmaCtfAdapter
/// @author Polymarket
contract Deploy is Script {
    /// @notice Deploys the Adapter
    /// @param ctf          - The ConditionalTokens Framework address
    /// @param finder       - The UMA Finder address
    function deploy(address ctf, address finder) public returns (address adapter) {
        vm.startBroadcast();
        adapter = address(new UmaCtfAdapter(ctf, finder));
        vm.stopBroadcast();
    }
}
