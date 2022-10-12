// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Data, AdapterHelper } from "./dev/AdapterHelper.sol";

import { IAddressWhitelist } from "src/interfaces/IAddressWhitelist.sol";

contract UMaCtfAdapterTest is AdapterHelper {
    function testSetup() public {
        assertEq(whitelist, address(adapter.collateralWhitelist()));
        assertEq(ctf, address(adapter.ctf()));
        assertEq(optimisticOracle, address(adapter.optimisticOracle()));
        assertTrue(IAddressWhitelist(whitelist).isOnWhitelist(usdc));
    }

    function testAuth() public {
        vm.expectEmit(true, true, true, true);
        emit NewAdmin(admin, henry);
        
        vm.prank(admin);
        adapter.addAdmin(henry);
        assertTrue(adapter.isAdmin(henry));

        vm.expectEmit(true, true, true, true);
        emit RemovedAdmin(admin, henry);

        vm.prank(admin);
        adapter.removeAdmin(henry);
        assertFalse(adapter.isAdmin(henry));
    }

    function testAuthNotAdmin() public {
        vm.expectRevert(NotAdmin.selector);
        adapter.addAdmin(address(1));
    }

    function testAuthRenounce() public {
        // Non admin cannot renounce
        vm.expectRevert(NotAdmin.selector);
        vm.prank(address(12));
        adapter.renounceAdmin();
        
        // Successfully renounces the admin role
        vm.prank(admin);
        adapter.renounceAdmin();
        assertFalse(adapter.isAdmin(admin));
    }

    function testInitializeZeroRewardAndBond() public {
        bytes memory ancillaryData = hex"569e599c2f623949c0d74d7bf006f8a4f68b911876d6437c1db4ad4c3eb21e68682fb8168b75eb23d3994383a40643d73d59";
    
        bytes32 expectedQuestionID = keccak256(ancillaryData);
        vm.expectEmit(true, true, true, true);
        emit QuestionInitialized(expectedQuestionID, block.timestamp, admin, ancillaryData, usdc, 0, 0);

        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0);

        assertTrue(adapter.isInitialized(expectedQuestionID));

        Data memory data = getData(expectedQuestionID);
        assertEq(block.timestamp, data.requestTimestamp);
        assertEq(admin, data.creator);
        assertEq(ancillaryData, data.ancillaryData);
        assertEq(usdc, data.rewardToken);
        assertEq(0, data.reward);
        assertFalse(data.paused);
        assertFalse(data.resolved);
    }
}
