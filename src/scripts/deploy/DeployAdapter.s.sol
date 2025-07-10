// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { UmaCtfAdapter } from "src/UmaCtfAdapter.sol";

/// @title DeployAdapter
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

        if(!_verifyStatePostDeployment(admin, ctf, adapter)){
            revert("state verification post deployment failed");
        }
    }

    function _verifyStatePostDeployment(address admin, address ctf, address adapter) internal view returns (bool) {
        UmaCtfAdapter ctfAdapter = UmaCtfAdapter(adapter);
        
        if (ctfAdapter.isAdmin(msg.sender)) revert("Deployer admin not renounced");
        if (!ctfAdapter.isAdmin(admin)) revert("Adapter admin not set");        
        if (address(ctfAdapter.ctf()) != ctf) revert("Unexpected ConditionalTokensFramework set on adapter");

        return true;
    }
}
