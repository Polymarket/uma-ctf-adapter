// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AdapterHelper } from "./dev/AdapterHelper.sol";

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
}
