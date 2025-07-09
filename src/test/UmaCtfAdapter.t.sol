// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AdapterHelper } from "./dev/AdapterHelper.sol";
import { IAddressWhitelist } from "src/interfaces/IAddressWhitelist.sol";
import { IOptimisticOracleV2, Request } from "src/interfaces/IOptimisticOracleV2.sol";

import { QuestionData } from "src/UmaCtfAdapter.sol";

contract UmaCtfAdapterTest is AdapterHelper {
    function testSetup() public {
        assertEq(whitelist, address(adapter.collateralWhitelist()));
        assertEq(ctf, address(adapter.ctf()));
        assertEq(optimisticOracle, address(adapter.optimisticOracle()));
        assertTrue(IAddressWhitelist(whitelist).isOnWhitelist(usdc));
    }

    function testInitialize() public {
        uint256 reward = 1_000_000;
        uint256 bond = 10_000_000_000;

        vm.expectEmit(true, true, true, true);
        emit QuestionInitialized(questionID, block.timestamp, admin, appendedAncillaryData, usdc, reward, bond);

        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, reward, bond, 0);

        // Assert the QuestionData fields in storage
        QuestionData memory data = adapter.getQuestion(questionID);
        assertEq(block.timestamp, data.requestTimestamp);
        assertEq(admin, data.creator);
        assertEq(appendedAncillaryData, data.ancillaryData);
        assertEq(usdc, data.rewardToken);
        assertEq(reward, data.reward);
        assertEq(bond, data.proposalBond);
        assertFalse(data.paused);
        assertFalse(data.resolved);

        // Assert the Optimistic Oracle Request
        Request memory request = getRequest(data.requestTimestamp, data.ancillaryData);
        assertEq(address(0), request.proposer);
        assertEq(address(0), request.disputer);
        assertEq(usdc, address(request.currency));
        assertEq(reward, request.reward);
        assertEq(1_500_000_000, request.finalFee);
        assertTrue(request.requestSettings.eventBased);
        assertTrue(request.requestSettings.callbackOnPriceDisputed);
    }

    function testInitializeZeroRewardAndBond() public {
        vm.expectEmit(true, true, true, true);
        emit QuestionInitialized(questionID, block.timestamp, admin, appendedAncillaryData, usdc, 0, 0);

        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0, 0);

        assertTrue(adapter.isInitialized(questionID));

        QuestionData memory data = adapter.getQuestion(questionID);
        assertEq(block.timestamp, data.requestTimestamp);
        assertEq(admin, data.creator);
        assertEq(appendedAncillaryData, data.ancillaryData);
        assertEq(usdc, data.rewardToken);
        assertEq(0, data.reward);
        assertEq(0, data.proposalBond);
        assertFalse(data.paused);
        assertFalse(data.resolved);
    }

    function testInitializeCustomLiveness() public {
        uint256 liveness = 10 days;

        vm.expectEmit(true, true, true, true);
        emit QuestionInitialized(questionID, block.timestamp, admin, appendedAncillaryData, usdc, 0, 0);

        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0, liveness);

        assertTrue(adapter.isInitialized(questionID));

        QuestionData memory data = adapter.getQuestion(questionID);
        assertEq(block.timestamp, data.requestTimestamp);
        assertEq(admin, data.creator);
        assertEq(appendedAncillaryData, data.ancillaryData);
        assertEq(usdc, data.rewardToken);
        assertEq(0, data.reward);
        assertEq(0, data.proposalBond);
        assertEq(liveness, data.liveness);
        assertFalse(data.paused);
        assertFalse(data.resolved);

        Request memory request = getRequest(data.requestTimestamp, data.ancillaryData);
        assertEq(request.requestSettings.customLiveness, liveness);
    }

    function testInitializeRevertOnSameQuestion() public {
        // Init Question
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0, 0);

        // Revert when initializing the same question
        vm.expectRevert(Initialized.selector);
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0, 0);
    }

    function testInitializeRevertInsufficientRewardBalance() public {
        // Revert when caller does not have tokens or allowance on the adapter
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(carla);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);
    }

    function testInitializeRevertUnsupportedRewardToken() public {
        // Deploy a new ERC20 token to be used as reward token
        address tkn = deployToken("Test Token", "TST");
        vm.prank(admin);
        dealAndApprove(tkn, admin, address(adapter), type(uint256).max);

        // Revert as the token is not supported
        vm.expectRevert(UnsupportedToken.selector);
        vm.prank(admin);
        adapter.initialize(ancillaryData, tkn, 1_000_000, 10_000_000_000, 0);
    }

    function testInitializeRevertInvalidAncillaryData() public {
        // Revert since ancillaryData is invalid
        bytes memory data = hex"";
        vm.expectRevert(InvalidAncillaryData.selector);
        adapter.initialize(data, usdc, 1_000_000, 10_000_000_000, 0);
    }

    function testInitializeRevertCustomLiveness() public {
        uint256 livenessTooLong = 5200 weeks; // 100 years

        vm.expectRevert("Liveness too large");
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 0, 0, livenessTooLong);
    }

    function testPause() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

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

    function testPauseRevertNotAdmin() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.pause(questionID);

        vm.prank(admin);
        adapter.pause(questionID);

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.unpause(questionID);
    }

    function testPauseRevertAlreadyResolved() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data = adapter.getQuestion(questionID);
        proposeAndSettle(1 ether, data.requestTimestamp, data.ancillaryData);

        adapter.resolve(questionID);

        // Pausing an already resolved question reverts
        vm.expectRevert(Resolved.selector);
        vm.prank(admin);
        adapter.pause(questionID);
    }

    function testReady() public {
        // Valid case
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data = adapter.getQuestion(questionID);

        // Propose a price for the question
        int256 proposedPrice = 1 ether;
        proposeAndSettle(proposedPrice, data.requestTimestamp, data.ancillaryData);

        assertTrue(adapter.ready(questionID));

        // Uninitialized
        adapter.ready(keccak256("abc"));

        // Paused
        vm.prank(admin);
        adapter.pause(questionID);
        assertFalse(adapter.ready(questionID));
        vm.prank(admin);
        adapter.unpause(questionID);

        // Resolved
        adapter.resolve(questionID);
        assertFalse(adapter.ready(questionID));
    }

    function testResolve() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

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

    function testResolveYes() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data;
        data = adapter.getQuestion(questionID);

        // Price corresponds to YES
        int256 price = 1 ether;
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;
        proposeAndSettle(price, data.requestTimestamp, data.ancillaryData);

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionResolved(questionID, price, payouts);
        adapter.resolve(questionID);
    }

    function testResolveNo() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data;
        data = adapter.getQuestion(questionID);

        // Price corresponds to NO
        int256 price = 0;
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 1;
        proposeAndSettle(price, data.requestTimestamp, data.ancillaryData);

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionResolved(questionID, price, payouts);
        adapter.resolve(questionID);
    }

    function testResolveUnknown() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data;
        data = adapter.getQuestion(questionID);

        // Price corresponds to UNKNOWN
        int256 price = 0.5 ether;
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 1;
        proposeAndSettle(price, data.requestTimestamp, data.ancillaryData);

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionResolved(questionID, price, payouts);
        adapter.resolve(questionID);
    }

    function testResolveIgnorePrice() public {
        testPriceDisputed();

        QuestionData memory data;
        data = adapter.getQuestion(questionID);

        // Price corresponds to Ignore price, occurs if the dispute is escalated to the DVM and is too early
        int256 price = type(int256).min;

        // Mock the DVM dispute process and settle the Request with the ignore price
        // Propose
        propose(0, data.requestTimestamp, data.ancillaryData);

        // Dispute
        dispute(data.requestTimestamp, data.ancillaryData);

        oracle.setPriceExists(true);
        oracle.setPrice(price);
        settle(data.requestTimestamp, data.ancillaryData);

        // Second Dispute will refund the reward to the adapter
        assertBalance(usdc, address(adapter), data.reward);

        // Attempting to resolve the question with the Ignore price will reset the question
        vm.expectEmit(true, true, true, true);
        emit QuestionReset(questionID);
        adapter.resolve(questionID);
    }

    function testResolveRevertNotInitialized() public {
        vm.expectRevert(NotInitialized.selector);
        adapter.resolve(questionID);
    }

    function testResolveRevertUnavailablePrice() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.expectRevert(NotReadyToResolve.selector);
        adapter.resolve(questionID);
    }

    function testResolveRevertPaused() public {
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

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

    function testExpectedPayouts() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data;
        data = adapter.getQuestion(questionID);

        // Propose a price for the question
        int256 price = 1 ether;
        proposeAndSettle(price, data.requestTimestamp, data.ancillaryData);

        // Get Expected payouts if the price exists on the OO
        uint256[] memory expectedPayouts = adapter.getExpectedPayouts(questionID);
        // expectedPayouts = [1, 0]
        assertEq(1, expectedPayouts[0]);
        assertEq(0, expectedPayouts[1]);
    }

    function testExpectedPayoutsRevertNotInitialized() public {
        vm.expectRevert(NotInitialized.selector);
        // Reverts as it is uninitialized
        adapter.getExpectedPayouts(questionID);
    }

    function testExpectedPayoutsRevertPriceNotAvailable() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.expectRevert(PriceNotAvailable.selector);
        // Reverts as the price is not available from the OO
        adapter.getExpectedPayouts(questionID);
    }

    function testExpectedPayoutsRevertIgnorePriceReceived() public {
        testPriceDisputed();

        QuestionData memory data = adapter.getQuestion(questionID);

        // Propose
        propose(0, data.requestTimestamp, data.ancillaryData);

        // Dispute
        dispute(data.requestTimestamp, data.ancillaryData);

        // Mock the DVM dispute process and settle the Request with the ignore price
        int256 price = type(int256).min;
        oracle.setPriceExists(true);
        oracle.setPrice(price);
        settle(data.requestTimestamp, data.ancillaryData);

        // Reverts as the price on the OO is invalid
        vm.expectRevert(InvalidOOPrice.selector);
        adapter.getExpectedPayouts(questionID);
    }

    function testExpectedPayoutsRevertPaused() public {
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        adapter.pause(questionID);

        vm.expectRevert(Paused.selector);
        // Reverts as the question is paused
        adapter.getExpectedPayouts(questionID);
    }

    function testExpectedPayoutsRevertFlagged() public {
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        adapter.flag(questionID);

        vm.expectRevert(Flagged.selector);
        // Reverts as the question is flagged
        adapter.getExpectedPayouts(questionID);
    }

    function testExpectedPayoutsRevertResolveManually() public {
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        // Flag and manual resolve the question
        adapter.flag(questionID);
        fastForward(adapter.SAFETY_PERIOD());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;
        adapter.resolveManually(questionID, payouts);

        // Reverts as the question is flagged
        vm.expectRevert(Flagged.selector);
        adapter.getExpectedPayouts(questionID);
    }

    function testFlag() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.prank(admin);
        adapter.flag(questionID);

        assertTrue(adapter.isFlagged(questionID));

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.flag(questionID);
    }

    function testFlagRevertNotAdmin() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.flag(questionID);
    }

    function testFlagRevertNotInitialized() public {
        vm.expectRevert(NotInitialized.selector);
        vm.prank(admin);
        adapter.flag(questionID);
    }

    function testFlagRevertAlreadyResolved() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data = adapter.getQuestion(questionID);
        proposeAndSettle(1 ether, data.requestTimestamp, data.ancillaryData);

        // Resolve the question
        adapter.resolve(questionID);

        // Flag an already resolved question
        vm.expectRevert(Resolved.selector);
        vm.prank(admin);
        adapter.flag(questionID);
    }

    function testUnflag() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.prank(admin);
        adapter.flag(questionID);

        QuestionData memory data;
        data = adapter.getQuestion(questionID);
        assertTrue(data.manualResolutionTimestamp > 0);

        vm.expectEmit(true, true, true, true);
        emit QuestionUnflagged(questionID);

        vm.prank(admin);
        adapter.unflag(questionID);

        // Assert state post unflag
        data = adapter.getQuestion(questionID);
        assertEq(0, data.manualResolutionTimestamp);
        assertFalse(data.paused);

    }

    function testUnflagRevertNotAdmin() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.prank(admin);
        adapter.flag(questionID);

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.unflag(questionID);
    }

    function testUnflagRevertNotInitialized() public {
        vm.expectRevert(NotInitialized.selector);
        vm.prank(admin);
        adapter.unflag(questionID);
    }

    function testUnflagRevertAlreadyResolved() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.prank(admin);
        adapter.flag(questionID);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;
        fastForward(adapter.SAFETY_PERIOD());

        vm.prank(admin);
        adapter.resolveManually(questionID, payouts);

        // Attempt unflag an already resolved question
        vm.expectRevert(Resolved.selector);
        vm.prank(admin);
        adapter.unflag(questionID);
    }

    function testUnflagRevertSafetyPeriodPassed() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        vm.prank(admin);
        adapter.flag(questionID);

        fastForward(adapter.SAFETY_PERIOD());

        // Attempt unflag a question after the safety period has passed
        vm.expectRevert(SafetyPeriodPassed.selector);
        vm.prank(admin);
        adapter.unflag(questionID);
    }

    function testResolveManually() public {
        fastForward(100);

        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        // Flag the question for manual resolution
        adapter.flag(questionID);

        QuestionData memory data;

        // Ensure the relevant flags are set, meaning, the question is paused and the manualResolutionTimestamp is set
        data = adapter.getQuestion(questionID);
        assertTrue(data.paused);
        assertTrue(data.manualResolutionTimestamp > 0);

        // Fast forward time past the SAFETY_PERIOD
        fastForward(adapter.SAFETY_PERIOD());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionManuallyResolved(questionID, payouts);

        // Manual resolve the question
        adapter.resolveManually(questionID, payouts);

        // Check the flags post manual resolution
        data = adapter.getQuestion(questionID);
        assertTrue(data.resolved);
    }

    function testResolveManuallyPaused() public {
        // Manual resolution will still affect paused questions
        fastForward(100);

        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        // Pause the question
        adapter.pause(questionID);

        // Flag the question for manual resolution
        adapter.flag(questionID);

        // Fast forward time past the SAFETY_PERIOD
        fastForward(adapter.SAFETY_PERIOD());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionManuallyResolved(questionID, payouts);

        // Manual resolve the question
        adapter.resolveManually(questionID, payouts);
        QuestionData memory data = adapter.getQuestion(questionID);
        assertTrue(data.resolved);
    }

    function testResolveManuallyWhenRefundExists() public {
        // Initialize and propose/dispute a question
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data;
        data = adapter.getQuestion(questionID);

        propose(1 ether, data.requestTimestamp, data.ancillaryData);
        dispute(data.requestTimestamp, data.ancillaryData);

        fastForward(100);

        data = adapter.getQuestion(questionID);

        // Second round of propose/dispute, so refund now exists on the Adapter
        propose(1 ether, data.requestTimestamp, data.ancillaryData);
        dispute(data.requestTimestamp, data.ancillaryData);

        // Assert that the reward now exists on the Adapter after refund
        assertBalance(usdc, address(adapter), data.reward);

        // Flag the question for manual resolution
        vm.prank(admin);
        adapter.flag(questionID);

        // Ensure the relevant flags are set, meaning, the question is paused and the manualResolutionTimestamp is set
        data = adapter.getQuestion(questionID);
        assertTrue(data.paused);
        assertTrue(data.manualResolutionTimestamp > 0);

        // Fast forward time past the safety period
        fastForward(adapter.SAFETY_PERIOD());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 1;

        // Assert refund transfer occured
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(adapter), data.creator, data.reward);

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionManuallyResolved(questionID, payouts);

        // Manually resolve the question
        vm.prank(admin);
        adapter.resolveManually(questionID, payouts);

        // Assert state post manual resolution

        // Refund transferred to creator, adapter balance is empty
        assertBalance(usdc, address(adapter), 0);

        data = adapter.getQuestion(questionID);
        assertTrue(data.resolved);
        assertTrue(data.refund);
    }

    function testResolveManuallyRevertNotFlagged() public {
        fastForward(100);
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;
        vm.expectRevert(NotFlagged.selector);
        adapter.resolveManually(questionID, payouts);
    }

    function testResolveManuallyRevertSafetyPeriod() public {
        fastForward(100);
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        adapter.flag(questionID);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectRevert(SafetyPeriodNotPassed.selector);
        adapter.resolveManually(questionID, payouts);
    }

    function testResolveManuallyRevertInvalidPayouts() public {
        fastForward(100);
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        adapter.flag(questionID);

        // Invalid payout
        uint256[] memory invalidPayouts = new uint256[](4);
        invalidPayouts[0] = 0;
        invalidPayouts[1] = 0;
        invalidPayouts[2] = 1;
        invalidPayouts[3] = 6;

        vm.expectRevert(InvalidPayouts.selector);
        adapter.resolveManually(questionID, invalidPayouts);
    }

    function testResolveManuallyRevertNotAdmin() public {
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);
        adapter.flag(questionID);

        vm.stopPrank();

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.resolveManually(questionID, payouts);
    }

    function testResolveManuallyRevertNotInitialized() public {
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectRevert(NotInitialized.selector);
        vm.prank(admin);
        adapter.resolveManually(questionID, payouts);
    }

    function testIsValidPayoutArray() public {
        uint256[] memory payouts;
        
        // Valid payout arrays
        // [0, 1]
        payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 1;
        assertTrue(isValidPayoutArray(payouts));

        // [1, 0]
        payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;
        assertTrue(isValidPayoutArray(payouts));

        // [1, 1]
        payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 1;
        assertTrue(isValidPayoutArray(payouts));

        // Invalid cases
        // Invalid length: [1, 0, 1]
        payouts = new uint256[](3);
        payouts[0] = 1;
        payouts[1] = 0;
        payouts[2] = 1;
        assertFalse(isValidPayoutArray(payouts));
        
        // [3, 4]
        payouts = new uint256[](2);
        payouts[0] = 3;
        payouts[1] = 4;
        assertFalse(isValidPayoutArray(payouts));

        // [1, 4]
        payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 4;
        assertFalse(isValidPayoutArray(payouts));

        // [3, 0]
        payouts = new uint256[](2);
        payouts[0] = 3;
        payouts[1] = 0;
        assertFalse(isValidPayoutArray(payouts));

        // [0, 0]
        payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 0;
        assertFalse(isValidPayoutArray(payouts));
    }

    function testProposed() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data = adapter.getQuestion(questionID);

        // Propose a price for the question
        propose(1 ether, data.requestTimestamp, data.ancillaryData);

        // Assert state of the OO Request post-proposal
        Request memory request = getRequest(data.requestTimestamp, data.ancillaryData);

        assertEq(request.proposer, proposer);
        assertEq(request.proposedPrice, 1 ether);
        assertEq(request.expirationTime, block.timestamp + getDefaultLiveness());
        assertEq(request.requestSettings.bond, 10_000_000_000);
    }

    function testPriceDisputed() public {
        uint256 reward = 1_000_000;
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, reward, 10_000_000_000, 0);

        QuestionData memory data;

        data = adapter.getQuestion(questionID);
        uint256 initialTimestamp = data.requestTimestamp;

        // Propose a price for the question
        int256 proposedPrice = 1 ether;
        propose(proposedPrice, initialTimestamp, data.ancillaryData);

        fastForward(100);

        // Assert the reward refund from the OO to the Adapter
        vm.expectEmit(true, true, true, true);
        emit Transfer(optimisticOracle, address(adapter), reward);

        // Assert the QuestionReset event
        vm.expectEmit(true, true, true, true);
        emit QuestionReset(questionID);

        // Dispute the proposal, triggering the priceDisputed callback, resetting the question and creating a new OO request
        dispute(initialTimestamp, data.ancillaryData);

        data = adapter.getQuestion(questionID);
        assertTrue(data.requestTimestamp > initialTimestamp);
    }

    function testPriceDisputedResolveAfterDispute() public {
        // Init and dispute a proposal
        testPriceDisputed();

        QuestionData memory data = adapter.getQuestion(questionID);

        // Propose and settle a new price for the previously reset question
        int256 price = 1 ether;
        proposeAndSettle(price, data.requestTimestamp, data.ancillaryData);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionResolved(questionID, price, payouts);

        // Resolve the question
        adapter.resolve(questionID);
    }

    function testPriceDisputedRevertNotOO() public {
        vm.expectRevert(NotOptimisticOracle.selector);
        vm.prank(carla);
        adapter.priceDisputed(identifier, block.timestamp, ancillaryData, 1_000_000);
    }

    function testPriceDisputedDvmRespondsNo() public {
        // Initalize and dispute a question
        testPriceDisputed();

        QuestionData memory data;
        data = adapter.getQuestion(questionID);
        uint256 timestamp = data.requestTimestamp;
        assertTrue(data.reset);

        propose(0, data.requestTimestamp, data.ancillaryData);

        // Subsequent disputes to the new price request will not reset the question
        // Ensuring that there are at most 2 requests for a question
        dispute(data.requestTimestamp, data.ancillaryData);

        data = adapter.getQuestion(questionID);

        // The second dispute will set the refund flag but will not affect request timestamp
        assertEq(timestamp, data.requestTimestamp);
        assertTrue(data.refund);

        // Mock the DVM dispute process and settle the Request with a NO price
        int256 noPrice = 0;
        oracle.setPriceExists(true);
        oracle.setPrice(noPrice);
        settle(data.requestTimestamp, data.ancillaryData);

        // Resolve the Question and assert that the price used is from the second dispute
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 1;

        // Assert that the reward now exists on the Adapter after refund
        assertBalance(usdc, address(adapter), data.reward);

        // Assert the refund transfer to the creator
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(adapter), data.creator, data.reward);

        vm.expectEmit(true, true, true, true);
        emit QuestionResolved(questionID, noPrice, payouts);

        adapter.resolve(questionID);
        // Assert balances post resolution
        assertBalance(usdc, address(adapter), 0);
    }

    function testPriceDisputedDvmRespondsYes() public {
        // Initalize and dispute a question
        testPriceDisputed();

        QuestionData memory data;
        data = adapter.getQuestion(questionID);
        uint256 timestamp = data.requestTimestamp;

        propose(0, data.requestTimestamp, data.ancillaryData);

        // Subsequent disputes to the new price request will not reset the question
        // Ensuring that there are at most 2 requests for a question
        dispute(data.requestTimestamp, data.ancillaryData);

        data = adapter.getQuestion(questionID);

        // The second dispute will set the refund flag, and leave the requestTimestamp unchanged
        assertEq(timestamp, data.requestTimestamp);
        assertTrue(data.refund);

        // Mock the DVM dispute process and settle the Request with a NO price
        int256 price = 1 ether;
        oracle.setPriceExists(true);
        oracle.setPrice(price);
        settle(data.requestTimestamp, data.ancillaryData);

        // Resolve the Question and assert that the price used is from the second dispute
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        // Assert that the reward now exists on the Adapter after refund
        assertBalance(usdc, address(adapter), data.reward);

        // Assert the refund transfer to the creator
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(adapter), data.creator, data.reward);

        vm.expectEmit(true, true, true, true);
        emit QuestionResolved(questionID, price, payouts);

        adapter.resolve(questionID);
        assertBalance(usdc, address(adapter), 0);
    }

    function testPriceDisputedDvmRespondsIgnore() public {
        // Initalize and dispute a question
        testPriceDisputed();

        QuestionData memory data;
        data = adapter.getQuestion(questionID);
        uint256 timestamp = data.requestTimestamp;

        // Initialize another round of proposals and disputes, forcing the OO to fallback to DVM dispute process
        // Propose
        propose(0, timestamp, data.ancillaryData);

        // Dispute, will not reset the question
        // But will refund the reward to the Adapter

        // Assert refund transfer event on dispute
        vm.expectEmit(true, true, true, true);
        emit Transfer(optimisticOracle, address(adapter), data.reward);
        dispute(timestamp, data.ancillaryData);

        // Assert refund balance on adapter
        assertBalance(usdc, address(adapter), data.reward);

        // Mock the DVM dispute process and settle the Request with the ignore price
        int256 ignorePrice = type(int256).min;
        oracle.setPriceExists(true);
        oracle.setPrice(ignorePrice);
        settle(timestamp, data.ancillaryData);

        // Attempt to resolve the Question
        // Since the DVM returns the ignore price, reset the question
        // Paying for the price request from the Adapter's token balance

        // Assert price request payment
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(adapter), optimisticOracle, data.reward);

        // Assert that the question has been reset
        vm.expectEmit(true, true, true, true);
        emit QuestionReset(questionID);

        adapter.resolve(questionID);

        // Assert token balance on Adapter after paying request reward
        assertBalance(usdc, address(adapter), 0);

        // Assert that the question parameters in storage have been updated
        data = adapter.getQuestion(questionID);
        assertTrue(data.requestTimestamp > timestamp);
        // Assert that the refund flag is now false, as the question has been reset
        assertFalse(data.refund);

        // Assert that there is a new OO price request for the question
        Request memory request = getRequest(data.requestTimestamp, data.ancillaryData);
        assertEq(address(0), request.proposer);
        assertEq(address(0), request.disputer);
        assertEq(usdc, address(request.currency));
    }

    function testPriceDisputedResolveManuallyd() public {
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data;
        data = adapter.getQuestion(questionID);
        uint256 timestamp = data.requestTimestamp;

        adapter.flag(questionID);

        fastForward(adapter.SAFETY_PERIOD());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 1;

        // Manual resolve the question
        adapter.resolveManually(questionID, payouts);
        vm.stopPrank();

        // Propose the OO Request
        propose(0, timestamp, data.ancillaryData);

        // Dispute the request, executing the priceDisputed callback of the already resolved question
        // Since the question is already resolved, the priceDisputed callback will refund the reward to the
        // question creator *without* updating the request timestamp.

        // Assert the refund from Adapter to the creator
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(adapter), data.creator, data.reward);

        dispute(timestamp, data.ancillaryData);

        // Assert state post dispute
        data = adapter.getQuestion(questionID);
        // Timestamp remains unchanged
        assertEq(timestamp, data.requestTimestamp);
    }

    function testReset() public {
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);
        fastForward(10);

        vm.expectEmit(true, true, true, true);
        emit QuestionReset(questionID);

        vm.prank(admin);
        adapter.reset(questionID);
        QuestionData memory data = adapter.getQuestion(questionID);
        assertFalse(data.refund);
    }

    function testResetWhenRefundExists() public {
        // Initialize a question and propose/dispute it
        vm.prank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        QuestionData memory data;
        data = adapter.getQuestion(questionID);

        propose(0, data.requestTimestamp, data.ancillaryData);
        dispute(data.requestTimestamp, data.ancillaryData);

        fastForward(100);

        data = adapter.getQuestion(questionID);

        // Propose/dispute again, forcing a fallback to the DVM
        propose(0, data.requestTimestamp, data.ancillaryData);
        dispute(data.requestTimestamp, data.ancillaryData);

        // Reward tokens should now exist on the adapter
        assertBalance(usdc, address(adapter), data.reward);

        fastForward(100);

        // Reset the question, refunding the reward to the question creator
        // And paying for the new price request from the caller
        // Assert the refund transfer
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(adapter), data.creator, data.reward);

        // Assert the question reset
        vm.expectEmit(true, true, true, true);
        emit QuestionReset(questionID);
        vm.prank(admin);
        adapter.reset(questionID);

        // Assert state post reset
        // Adapter should have no reward tokens
        assertBalance(usdc, address(adapter), 0);

        data = adapter.getQuestion(questionID);

        // Refund flag false, due to reset
        assertFalse(data.refund);
    }

    function testResetRevertNotInitialized() public {
        vm.expectRevert(NotInitialized.selector);
        vm.prank(admin);
        adapter.reset(questionID);
    }

    function testResetRevertResolved() public {
        testResolve();

        vm.expectRevert(Resolved.selector);
        vm.prank(admin);
        adapter.reset(questionID);
    }

    function testResetAlreadyReset() public {
        testReset();

        uint256 timestamp = block.timestamp;

        fastForward(100);

        // Resetting an already reset question is allowed
        vm.prank(admin);
        adapter.reset(questionID);
        QuestionData memory data = adapter.getQuestion(questionID);

        assertTrue(data.requestTimestamp > timestamp);
        assertFalse(data.refund);
    }
}
