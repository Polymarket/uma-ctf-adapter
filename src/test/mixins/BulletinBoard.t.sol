// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";

import { BulletinBoard } from "src/mixins/BulletinBoard.sol";
import { IBulletinBoardEE, AncillaryDataUpdate } from "src/interfaces/IBulletinBoard.sol";

contract BBHarness is BulletinBoard { }

contract BulletinBoardTest is Test, IBulletinBoardEE {
    address bob = address(1);

    BBHarness public harness;

    function setUp() public {
        harness = new BBHarness();
    }

    function testPostUpdate() public {
        bytes32 questionID = hex"1234";
        bytes memory update = hex"abcd";

        vm.expectEmit(true, true, true, true);
        emit AncillaryDataUpdated(questionID, bob, update);

        vm.prank(bob);
        harness.postUpdate(questionID, update);
    }

    function testPostUpdateMultiple() public {
        bytes32 questionID = hex"1234";
        bytes memory update = hex"abcd";

        vm.prank(bob);
        harness.postUpdate(questionID, update);

        bytes memory updateB = hex"bacd";
        vm.prank(bob);
        harness.postUpdate(questionID, updateB);

        AncillaryDataUpdate[] memory updates = harness.getUpdates(questionID, bob);
        assertEq(updates.length, 2);

        // If multiple updates, GetLatestUpdate will return the most recent update only
        AncillaryDataUpdate memory mostRecentUpdate = harness.getLatestUpdate(questionID, bob);
        assertEq(mostRecentUpdate.timestamp, block.timestamp);
        assertEq(mostRecentUpdate.update, updateB);
    }

    function testGetUpdate() public {
        bytes32 questionID = hex"1234";
        bytes memory update = hex"abcd";

        // Get updates when none exist, returns empty list
        AncillaryDataUpdate[] memory updates = harness.getUpdates(questionID, bob);
        assertEq(updates.length, 0);

        // Post an ancillary data update
        vm.prank(bob);
        harness.postUpdate(questionID, update);

        // Get the update and assert its state
        updates = harness.getUpdates(questionID, bob);
        assertEq(updates.length, 1);
        AncillaryDataUpdate memory data = updates[0];

        assertEq(data.update, update);
        assertEq(data.timestamp, block.timestamp);
    }

    function testGetLatestUpdate() public {
        bytes32 questionID = hex"1234";
        bytes memory update = hex"abcd";

        // Get latest update when none exist, returns empty struct
        AncillaryDataUpdate memory data = harness.getLatestUpdate(questionID, bob);
        assertEq(data.update, "");
        assertEq(data.timestamp, 0);

        // Post Update
        vm.prank(bob);
        harness.postUpdate(questionID, update);

        data = harness.getLatestUpdate(questionID, bob);
        assertEq(data.update, update);
        assertEq(data.timestamp, block.timestamp);
    }
}
