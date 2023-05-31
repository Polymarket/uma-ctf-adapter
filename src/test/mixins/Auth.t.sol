// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";

import { Auth } from "src/mixins/Auth.sol";
import { IAuthEE } from "src/interfaces/IAuth.sol";

contract AuthHarness is Auth {
    function useOnlyAdmin() public onlyAdmin { }
}

contract AuthTest is Test, IAuthEE {
    address admin = address(1);
    address brian = address(2);
    address carla = address(3);

    AuthHarness public harness;

    function setUp() public {
        vm.prank(admin);
        harness = new AuthHarness();
    }

    function testIsAdmin() public {
        assertTrue(harness.isAdmin(admin));
        assertFalse(harness.isAdmin(brian));
    }

    function testAddAdmin() public {
        vm.expectEmit(true, true, true, true);
        emit NewAdmin(admin, brian);

        vm.prank(admin);
        harness.addAdmin(brian);
    }

    function testOnlyAdminSuccess() public {
        vm.prank(admin);
        harness.useOnlyAdmin();
    }

    function testOnlyAdminRevert() public {
        vm.expectRevert(NotAdmin.selector);
        harness.useOnlyAdmin();
    }

    function testAddAdminRevert() public {
        vm.prank(brian);
        vm.expectRevert(NotAdmin.selector);
        harness.addAdmin(brian);
    }

    function testRemoveAdmin() public {
        vm.prank(admin);
        harness.addAdmin(carla);

        vm.expectEmit(true, true, true, true);
        emit RemovedAdmin(admin, carla);

        vm.prank(admin);
        harness.removeAdmin(carla);

        assertFalse(harness.isAdmin(carla));
    }

    function testRenounceAdmin() public {
        vm.prank(admin);
        harness.renounceAdmin();
        emit RemovedAdmin(admin, admin);

        assertFalse(harness.isAdmin(admin));
    }
}
