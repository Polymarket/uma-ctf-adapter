// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { UmaCtfAdapter } from "src/UmaCtfAdapter.sol";

/// @title Deploy
/// @notice Script to deploy the UmaCtfAdapter
/// @author Polymarket
contract DeployAdapter is Script {
    /// @notice Deploys the Adapter
    /// @param admin        - The admin for the Adapter
    /// @param ctf          - The ConditionalTokens Framework address
    /// @param finder       - The UMA Finder address
    function deployAdapter(address admin, address ctf, address finder) public returns (address adapter) {
        vm.startBroadcast();
        
        UmaCtfAdapter ctfAdapter = new UmaCtfAdapter(ctf, finder);
        
        // Add admin auth to the Admin address
        ctfAdapter.addAdmin(admin);

        // revoke deployer's auth
        ctfAdapter.renounceAdmin();

        adapter = address(ctfAdapter);

        vm.stopBroadcast();
    }
}
