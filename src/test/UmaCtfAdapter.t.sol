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

    function testAuthRevertNotAdmin() public {
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

    function testEmergencyResolve() public {
        fastForward(100);

        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        // Flag the question for emergency resolution
        adapter.flag(questionID);

        QuestionData memory data;

        // Ensure the relevant flags are set, meaning, the question is paused and the emergencyResolutionTimestamp is set
        data = adapter.getQuestion(questionID);
        assertTrue(data.paused);
        assertTrue(data.emergencyResolutionTimestamp > 0);

        // Fast forward time past the emergencySafetyPeriod
        fastForward(adapter.emergencySafetyPeriod());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionEmergencyResolved(questionID, payouts);

        // Emergency resolve the question
        adapter.emergencyResolve(questionID, payouts);

        // Check the flags post emergency resolution
        data = adapter.getQuestion(questionID);
        assertTrue(data.resolved);
    }

    function testEmergencyResolvePaused() public {
        // Emergency resolution will still affect paused questions
        fastForward(100);

        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        // Pause the question
        adapter.pause(questionID);

        // Flag the question for emergency resolution
        adapter.flag(questionID);

        // Fast forward time past the emergencySafetyPeriod
        fastForward(adapter.emergencySafetyPeriod());

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectEmit(true, true, true, true);
        emit ConditionResolution(conditionId, address(adapter), questionID, 2, payouts);

        vm.expectEmit(true, true, true, true);
        emit QuestionEmergencyResolved(questionID, payouts);

        // Emergency resolve the question
        adapter.emergencyResolve(questionID, payouts);
        QuestionData memory data = adapter.getQuestion(questionID);
        assertTrue(data.resolved);
    }

    function testEmergencyResolveRevertNotFlagged() public {
        fastForward(100);
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;
        vm.expectRevert(NotFlagged.selector);
        adapter.emergencyResolve(questionID, payouts);
    }

    function testEmergencyResolveRevertSafetyPeriod() public {
        fastForward(100);
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        adapter.flag(questionID);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectRevert(SafetyPeriodNotPassed.selector);
        adapter.emergencyResolve(questionID, payouts);
    }

    function testEmergencyResolveRevertInvalidPayouts() public {
        fastForward(100);
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);

        adapter.flag(questionID);

        uint256[] memory invalidPayouts = new uint256[](4);
        invalidPayouts[0] = 0;
        invalidPayouts[1] = 0;
        invalidPayouts[2] = 1;
        invalidPayouts[3] = 6;

        vm.expectRevert(InvalidPayouts.selector);
        adapter.emergencyResolve(questionID, invalidPayouts);
    }

    function testEmergencyResolveRevertNotAdmin() public {
        vm.startPrank(admin);
        adapter.initialize(ancillaryData, usdc, 1_000_000, 10_000_000_000, 0);
        adapter.flag(questionID);

        vm.stopPrank();

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectRevert(NotAdmin.selector);
        vm.prank(carla);
        adapter.emergencyResolve(questionID, payouts);
    }

    function testEmergencyResolveRevertNotInitialized() public {
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.expectRevert(NotInitialized.selector);
        vm.prank(admin);
        adapter.emergencyResolve(questionID, payouts);
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

    function testPriceDisputedAlreadyReset() public {
        // Initalize and dispute a question
        testPriceDisputed();

        QuestionData memory data = adapter.getQuestion(questionID);
        uint256 timestamp = data.requestTimestamp;
        assertTrue(data.reset);

        propose(0, data.requestTimestamp, data.ancillaryData);

        // Subsequent disputes to the new price request will not reset the question
        // Ensuring that there are at most 2 requests for a question
        dispute(data.requestTimestamp, data.ancillaryData);

        // The second dispute is a no-op, and the requestTimestamp is unchanged
        assertEq(timestamp, data.requestTimestamp);

        // Mock the DVM dispute process and settle the Request with a NO price
        int256 noPrice = 0;
        oracle.setPriceExists(true);
        oracle.setPrice(noPrice);
        settle(data.requestTimestamp, data.ancillaryData);

        // Resolve the Question and assert that the price used is from the second dispute
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 1;

        vm.expectEmit(true, true, true, true);
        emit QuestionResolved(questionID, noPrice, payouts);

        adapter.resolve(questionID);
    }

    function testPriceDisputedIgnorePriceReceived() public {
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

        // Assert that there is a new OO price request for the question
        Request memory request = getRequest(data.requestTimestamp, data.ancillaryData);
        assertEq(address(0), request.proposer);
        assertEq(address(0), request.disputer);
        assertEq(usdc, address(request.currency));
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

        assertTrue(data.reset);
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
    }
}
