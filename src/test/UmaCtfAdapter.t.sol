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
        emit QuestionInitialized(defaultQuestionID, block.timestamp, admin, defaultAncillaryData, usdc, reward, bond);

        vm.prank(admin);
        adapter.initialize(defaultAncillaryData, usdc, reward, bond);

        // Assert the QuestionData in storage
        QuestionData memory data = adapter.getQuestion(defaultQuestionID);
        assertEq(block.timestamp, data.requestTimestamp);
        assertEq(admin, data.creator);
        assertEq(defaultAncillaryData, data.ancillaryData);
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
        emit QuestionInitialized(defaultQuestionID, block.timestamp, admin, defaultAncillaryData, usdc, 0, 0);

        vm.prank(admin);
        adapter.initialize(defaultAncillaryData, usdc, 0, 0);

        assertTrue(adapter.isInitialized(defaultQuestionID));

        QuestionData memory data = adapter.getQuestion(defaultQuestionID);
        assertEq(block.timestamp, data.requestTimestamp);
        assertEq(admin, data.creator);
        assertEq(defaultAncillaryData, data.ancillaryData);
        assertEq(usdc, data.rewardToken);
        assertEq(0, data.reward);
        assertEq(0, data.proposalBond);
        assertFalse(data.paused);
        assertFalse(data.resolved);
    }

    function testInitializeRevertOnSameQuestion() public {
        // Init Question
        vm.prank(admin);
        adapter.initialize(defaultAncillaryData, usdc, 0, 0);

        // Revert when initializing the same question
        vm.expectRevert(Initialized.selector);
        adapter.initialize(defaultAncillaryData, usdc, 0, 0);
    }

    function testInitializeRevertInsufficientRewardBalance() public {
        uint256 reward = 1_000_000;
        uint256 bond = 10_000_000_000;

        // Revert when caller does not have tokens or allowance on the adapter
        vm.expectRevert("TransferHelper/STF");
        vm.prank(carla);
        adapter.initialize(defaultAncillaryData, usdc, reward, bond);
    }

    function testInitializeRevertUnsupportedRewardToken() public {
        uint256 reward = 1_000_000;
        uint256 bond = 10_000_000_000;

        // Deploy a new ERC20 token to be used as reward token
        address tkn = deployERC20("Test Token", "TST");
        vm.prank(admin);
        dealAndApprove(tkn, admin, address(adapter), type(uint256).max);

        // Revert when the reward token is not supported
        vm.expectRevert(UnsupportedToken.selector);
        vm.prank(admin);
        adapter.initialize(defaultAncillaryData, tkn, reward, bond);
    }
}
