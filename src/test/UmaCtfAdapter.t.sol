// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AdapterHelper } from "./dev/AdapterHelper.sol";

import { IAddressWhitelist } from "src/interfaces/IAddressWhitelist.sol";
import { IOptimisticOracleV2 } from "src/interfaces/IOptimisticOracleV2.sol";

import { QuestionData } from "src/UmaCtfAdapter.sol";

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

    function testInitialize() public {
        uint256 reward = 1_000_000;
        uint256 bond = 10_000_000_000;

        vm.expectEmit(true, true, true, true);
        emit QuestionInitialized(questionID, block.timestamp, admin, ancillaryData, usdc, reward, bond);

        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, reward, bond);

        // Assert the QuestionData in storage
        QuestionData memory data = adapter.getQuestion(questionID);
        assertEq(block.timestamp, data.requestTimestamp);
        assertEq(admin, data.creator);
        assertEq(ancillaryData, data.ancillaryData);
        assertEq(usdc, data.rewardToken);
        assertEq(reward, data.reward);
        assertEq(bond, data.proposalBond);
        assertFalse(data.paused);
        assertFalse(data.resolved);

        // Assert the Optimistic Oracle Request
        IOptimisticOracleV2.Request memory request = IOptimisticOracleV2(optimisticOracle).getRequest(
            address(adapter), bytes32("YES_OR_NO_QUERY"), data.requestTimestamp, data.ancillaryData
        );
        assertEq(address(0), request.proposer);
        assertEq(address(0), request.disputer);
        assertEq(reward, request.reward);
        assertEq(1_500_000_000, request.finalFee);
        assertTrue(request.requestSettings.eventBased);
        assertTrue(request.requestSettings.callbackOnPriceDisputed);
    }

    function testInitializeZeroRewardAndBond() public {
        vm.expectEmit(true, true, true, true);
        emit QuestionInitialized(questionID, block.timestamp, admin, ancillaryData, usdc, 0, 0);

        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0);

        assertTrue(adapter.isInitialized(questionID));

        QuestionData memory data = adapter.getQuestion(questionID);
        assertEq(block.timestamp, data.requestTimestamp);
        assertEq(admin, data.creator);
        assertEq(ancillaryData, data.ancillaryData);
        assertEq(usdc, data.rewardToken);
        assertEq(0, data.reward);
        assertEq(0, data.proposalBond);
        assertFalse(data.paused);
        assertFalse(data.resolved);
    }

    function testInitializeRevertOnSameQuestion() public {
        // Init Question
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0);

        // Revert when initializing the same question
        vm.expectRevert(Initialized.selector);
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0);
    }

    function testInitializeRevertInsufficientRewardBalance() public {
        // Revert when caller does not have tokens or allowance on the adapter
        vm.expectRevert("TransferHelper/STF");
        vm.prank(carla);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);
    }

    function testInitializeRevertUnsupportedRewardToken() public {
        // Deploy a new ERC20 token to be used as reward token
        address tkn = deployToken("Test Token", "TST");
        vm.prank(admin);
        dealAndApprove(tkn, admin, address(adapter), type(uint256).max);

        // Revert as the token is not supported
        vm.expectRevert(UnsupportedToken.selector);
        vm.prank(admin);
        adapter.initialize(ancillaryData, tkn, 1_000_000, 10_000_000_000);
    }

    function testInitializeRevertInvalidAncillaryData() public {
        // Revert since ancillaryData is invalid
        bytes memory ancillaryData = hex"";
        vm.expectRevert(InvalidAncillaryData.selector);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);
    }

    function testPause() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);

        vm.prank(admin);
        adapter.pause(questionID);
        assertTrue(adapter.getQuestion(questionID).paused);

        vm.prank(admin);
        adapter.unpause(questionID);
        assertFalse(adapter.getQuestion(questionID).paused);
    }

    function testPauseRevertNotInitialized() public {
        vm.expectRevert(NotInitialized.selector);
        vm.prank(admin);
        adapter.pause(questionID);
    }

    function testPauseRevertNonAdmin() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.pause(questionID);

        vm.prank(admin);
        adapter.pause(questionID);

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.unpause(questionID);
    }

    function testFlag() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);

        vm.prank(admin);
        adapter.flag(questionID);

        assertTrue(adapter.isFlagged(questionID));

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.flag(questionID);
    }

    function testReadyToResolve() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);

        QuestionData memory data = adapter.getQuestion(questionID);

        // Propose a price for the question
        int256 proposedPrice = 1 ether;
        proposeAndSettle(proposedPrice, data.requestTimestamp, data.ancillaryData);

        assertTrue(adapter.readyToResolve(questionID));
    }

    function testResolve() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);

        QuestionData memory data; 
        data = adapter.getQuestion(questionID);

        // Propose a price for the question
        int256 price = 1 ether;
        proposeAndSettle(price, data.requestTimestamp, data.ancillaryData);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectEmit(true, true, true, true);
        emit QuestionResolved(questionID, price, payouts);
        
        adapter.resolve(questionID);
        data = adapter.getQuestion(questionID);
        assertTrue(data.resolved);
    }

    function testResolveRevertNotInitialized() public {
        vm.expectRevert(NotReadyToResolve.selector);
        adapter.resolve(questionID);
    }

    function testResolveRevertUnavailablePrice() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);

        vm.expectRevert(NotReadyToResolve.selector);
        adapter.resolve(questionID);
    }

    function testResolveRevertPaused() public {
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000);
        
        adapter.pause(questionID);
        vm.stopPrank();

        vm.expectRevert(Paused.selector);
        adapter.resolve(questionID);
    }

    function testResolveRevertAlreadyResolved() public {
        testResolve();
        vm.expectRevert(Resolved.selector);
        adapter.resolve(questionID);
    }
}
