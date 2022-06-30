import hre, { deployments, ethers } from "hardhat";
import { HashZero } from "@ethersproject/constants";
import { expect } from "chai";
import { MockContract } from "@ethereum-waffle/mock-contract";
import { BigNumber } from "ethers";
import { MockConditionalTokens, TestERC20, UmaCtfAdapter } from "../../typechain";
import {
    deploy,
    deployMock,
    createAncillaryData,
    hardhatIncreaseTime,
    initializeQuestion,
    getMockRequest,
    getSignerForAddress,
} from "../helpers";
import { DESC, QUESTION_TITLE, emergencySafetyPeriod, MAX_ANCILLARY_DATA, ONE_ETHER } from "./constants";

const setup = deployments.createFixture(async () => {
    const signers = await hre.ethers.getSigners();
    const admin = signers[0];

    const ctf: MockConditionalTokens = await deploy<MockConditionalTokens>("MockConditionalTokens", {
        args: [],
        connect: admin,
    });
    const testRewardToken: TestERC20 = await deploy<TestERC20>("TestERC20", {
        args: ["TestERC20", "TST"],
        connect: admin,
    });

    // Mint TST tokens to admin
    await (await testRewardToken.mint(admin.address, BigNumber.from(ethers.utils.parseEther("1000000")))).wait();

    const optimisticOracle: MockContract = await deployMock("OptimisticOracleV2Interface");
    await optimisticOracle.mock.requestPrice.returns(0);
    await optimisticOracle.mock.settleAndGetPrice.returns(ONE_ETHER);
    await optimisticOracle.mock.setBond.returns(ethers.constants.One);
    await optimisticOracle.mock.setEventBased.returns();
    await optimisticOracle.mock.getRequest.returns(getMockRequest());
    await optimisticOracle.mock.setCallbacks.returns();

    const whitelist: MockContract = await deployMock("AddressWhitelistInterface");
    await whitelist.mock.isOnWhitelist.returns(true);

    const finderContract: MockContract = await deployMock("FinderInterface");

    await finderContract.mock.getImplementationAddress
        .withArgs(ethers.utils.formatBytes32String("OptimisticOracleV2"))
        .returns(optimisticOracle.address);

    await finderContract.mock.getImplementationAddress
        .withArgs(ethers.utils.formatBytes32String("CollateralWhitelist"))
        .returns(whitelist.address);

    const umaCtfAdapter: UmaCtfAdapter = await deploy<UmaCtfAdapter>("UmaCtfAdapter", {
        args: [ctf.address, finderContract.address],
        connect: admin,
    });

    // Approve TST token with admin signer as owner and adapter as spender
    await (await testRewardToken.connect(admin).approve(umaCtfAdapter.address, ethers.constants.MaxUint256)).wait();

    return {
        ctf,
        finderContract,
        optimisticOracle,
        whitelist,
        testRewardToken,
        umaCtfAdapter,
    };
});

describe("", function () {
    before(async function () {
        this.signers = {};
        const signers = await hre.ethers.getSigners();
        this.signers.admin = signers[0];
        this.signers.deployer = signers[1];
        this.signers.tester = signers[2];
    });

    describe("UMA CTF Adapter", function () {
        describe("Setup Tests", function () {
            let ctf: MockConditionalTokens;
            let optimisticOracle: MockContract;
            let umaCtfAdapter: UmaCtfAdapter;

            before(async function () {
                const deployment = await setup();
                ctf = deployment.ctf;
                optimisticOracle = deployment.optimisticOracle;
                umaCtfAdapter = deployment.umaCtfAdapter;
            });

            it("correctly authorizes users", async function () {
                expect(await umaCtfAdapter.wards(this.signers.admin.address)).eq(1);
                expect(await umaCtfAdapter.wards(this.signers.tester.address)).eq(0);

                // Authorize the user
                expect(await umaCtfAdapter.rely(this.signers.tester.address))
                    .to.emit(umaCtfAdapter, "AuthorizedUser")
                    .withArgs(this.signers.tester.address);

                // Deauthorize the user
                expect(await umaCtfAdapter.deny(this.signers.tester.address))
                    .to.emit(umaCtfAdapter, "DeauthorizedUser")
                    .withArgs(this.signers.tester.address);

                // Attempt to authorize without being authorized
                await expect(
                    umaCtfAdapter.connect(this.signers.tester).rely(this.signers.tester.address),
                ).to.be.revertedWith("Adapter/not-authorized");

                // Attempt to deauthorize without being authorized
                await expect(
                    umaCtfAdapter.connect(this.signers.tester).deny(this.signers.tester.address),
                ).to.be.revertedWith("Adapter/not-authorized");
            });

            it("correctly sets up contracts", async function () {
                const expectedCtf = await umaCtfAdapter.ctf();
                expect(ctf.address).eq(expectedCtf);

                const expectedOptimisticOracle = await umaCtfAdapter.optimisticOracle();
                expect(optimisticOracle.address).eq(expectedOptimisticOracle);
            });
        });

        describe("Question scenarios", function () {
            let ctf: MockConditionalTokens;
            let optimisticOracle: MockContract;
            let whitelist: MockContract;
            let testRewardToken: TestERC20;
            let umaCtfAdapter: UmaCtfAdapter;

            before(async function () {
                const deployment = await setup();
                ctf = deployment.ctf;
                optimisticOracle = deployment.optimisticOracle;
                whitelist = deployment.whitelist;
                testRewardToken = deployment.testRewardToken;
                umaCtfAdapter = deployment.umaCtfAdapter;
            });

            // Initialization tests
            it("correctly initializes a question with zero reward/bond", async function () {
                const ancillaryData = createAncillaryData(
                    ethers.utils.randomBytes(5).toString(),
                    ethers.utils.randomBytes(10).toString(),
                );
                const reward = 0;
                const proposalBond = 0;
                const outcomeSlotCount = 2;
                const expectedQuestionID = await umaCtfAdapter.getQuestionID(ancillaryData);
                const conditionID = await ctf.getConditionId(
                    umaCtfAdapter.address,
                    expectedQuestionID,
                    outcomeSlotCount,
                );

                // Initializing a question does the following:
                // 1. Stores the question parameters in Adapter storage,
                // 2. Prepares the question on the CTF
                // 3. Requests a price from the OO, paying the request reward
                expect(
                    await umaCtfAdapter.initializeQuestion(
                        ancillaryData,
                        testRewardToken.address,
                        reward,
                        proposalBond,
                    ),
                )
                    .to.emit(umaCtfAdapter, "QuestionInitialized")
                    .and.to.emit(ctf, "ConditionPreparation")
                    .withArgs(conditionID, umaCtfAdapter.address, expectedQuestionID, outcomeSlotCount);

                const returnedQuestionData = await umaCtfAdapter.questions(expectedQuestionID);

                // Verify question data stored
                expect(returnedQuestionData.creator).eq(this.signers.admin.address);
                expect(returnedQuestionData.ancillaryData).eq(ethers.utils.hexlify(ancillaryData));
                expect(returnedQuestionData.requestTimestamp).gt(0);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(0);

                // ensure paused defaults to false
                expect(returnedQuestionData.paused).eq(false);
            });

            it("correctly initializes a question with non-zero reward and bond", async function () {
                const ancillaryData = createAncillaryData(
                    ethers.utils.randomBytes(5).toString(),
                    ethers.utils.randomBytes(10).toString(),
                );
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");
                const outcomeSlotCount = 2;
                const expectedQuestionID = await umaCtfAdapter.getQuestionID(ancillaryData);

                const conditionID = await ctf.getConditionId(
                    umaCtfAdapter.address,
                    expectedQuestionID,
                    outcomeSlotCount,
                );
                const initializerBalance = await testRewardToken.balanceOf(this.signers.admin.address);

                expect(
                    await umaCtfAdapter
                        .connect(this.signers.admin)
                        .initializeQuestion(ancillaryData, testRewardToken.address, reward, proposalBond),
                )
                    .to.emit(umaCtfAdapter, "QuestionInitialized") // Question gets initialized
                    .and.to.emit(ctf, "ConditionPreparation") // Condition gets prepared on the CTF
                    .withArgs(conditionID, umaCtfAdapter.address, expectedQuestionID, outcomeSlotCount)
                    .and.to.emit(testRewardToken, "Transfer") // Transfer reward from caller to the Adapter
                    .withArgs(this.signers.admin.address, umaCtfAdapter.address, reward);

                const returnedQuestionData = await umaCtfAdapter.questions(expectedQuestionID);

                // Verify question data stored
                expect(returnedQuestionData.creator).eq(this.signers.admin.address);
                expect(returnedQuestionData.ancillaryData).eq(ethers.utils.hexlify(ancillaryData));
                expect(returnedQuestionData.requestTimestamp).gt(0);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(reward);
                expect(returnedQuestionData.proposalBond).eq(proposalBond);

                // Verify reward token allowance from Adapter with OO as spender
                const rewardTokenAllowance: BigNumber = await testRewardToken.allowance(
                    umaCtfAdapter.address,
                    optimisticOracle.address,
                );

                expect(rewardTokenAllowance).eq(ethers.constants.MaxUint256);

                // Verify that the initializeQuestion caller paid for the OO price request
                const initializerBalancePost = await testRewardToken.balanceOf(this.signers.admin.address);
                expect(initializerBalance.sub(initializerBalancePost).toString()).to.eq(reward.toString());
            });

            it("should revert when reinitializing the same question", async function () {
                // init question
                const ancillaryData = ethers.utils.randomBytes(10);

                await umaCtfAdapter.initializeQuestion(ancillaryData, testRewardToken.address, 0, 0);

                // reinitialize the same questionID
                await expect(
                    umaCtfAdapter.initializeQuestion(ancillaryData, testRewardToken.address, 0, 0),
                ).to.be.revertedWith("Adapter/already-initialized");
            });

            it("should revert if the initializer does not have reward tokens or allowance", async function () {
                const ancillaryData = createAncillaryData(
                    ethers.utils.randomBytes(5).toString(),
                    ethers.utils.randomBytes(10).toString(),
                );
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");

                await expect(
                    umaCtfAdapter
                        .connect(this.signers.tester)
                        .initializeQuestion(ancillaryData, testRewardToken.address, reward, proposalBond),
                ).to.be.revertedWith("TransferHelper/STF");
            });

            it("should revert when initializing with an unsupported reward token", async function () {
                const ancillaryData = ethers.utils.randomBytes(10);

                // Deploy a new token
                const unsupportedToken: TestERC20 = await deploy<TestERC20>("TestERC20", {
                    args: ["", ""],
                });

                await whitelist.mock.isOnWhitelist.withArgs(unsupportedToken.address).returns(false);

                // Reverts since the token isn't supported
                await expect(
                    umaCtfAdapter.initializeQuestion(ancillaryData, unsupportedToken.address, 0, 0),
                ).to.be.revertedWith("Adapter/unsupported-token");
            });

            it("should revert initialization if ancillary data is invalid", async function () {
                // reverts if ancillary data length == 0 or > MAX_ANCILLARY_DATA
                await expect(
                    umaCtfAdapter.initializeQuestion(ethers.utils.randomBytes(0), testRewardToken.address, 0, 0),
                ).to.be.revertedWith("Adapter/invalid-ancillary-data");

                await expect(
                    umaCtfAdapter.initializeQuestion(
                        ethers.utils.randomBytes(MAX_ANCILLARY_DATA + 1),
                        testRewardToken.address,
                        0,
                        0,
                    ),
                ).to.be.revertedWith("Adapter/invalid-ancillary-data");
            });

            // Pause tests
            it("should correctly pause resolution", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                expect(await umaCtfAdapter.connect(this.signers.admin).pauseQuestion(questionID))
                    .to.emit(umaCtfAdapter, "QuestionPaused")
                    .withArgs(questionID);

                const questionData = await umaCtfAdapter.questions(questionID);

                // Verify paused
                expect(questionData.paused).to.eq(true);
            });

            it("should correctly unpause resolution", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                expect(await umaCtfAdapter.connect(this.signers.admin).unPauseQuestion(questionID))
                    .to.emit(umaCtfAdapter, "QuestionUnpaused")
                    .withArgs(questionID);

                const questionData = await umaCtfAdapter.questions(questionID);

                // Verify unpaused
                expect(questionData.paused).to.eq(false);
            });

            it("pause should revert when signer is not admin", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                await expect(umaCtfAdapter.connect(this.signers.tester).pauseQuestion(questionID)).to.be.revertedWith(
                    "Adapter/not-authorized",
                );
            });

            it("unpause should revert when signer is not admin", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                await expect(umaCtfAdapter.connect(this.signers.tester).unPauseQuestion(questionID)).to.be.revertedWith(
                    "Adapter/not-authorized",
                );
            });

            it("pause should revert if question is not initialized", async function () {
                await expect(umaCtfAdapter.connect(this.signers.admin).pauseQuestion(HashZero)).to.be.revertedWith(
                    "Adapter/not-initialized",
                );
            });

            it("unpause should revert if question is not initialized", async function () {
                await expect(umaCtfAdapter.connect(this.signers.admin).unpauseQuestion(HashZero)).to.be.revertedWith(
                    "Adapter/not-initialized",
                );
            });
        });

        describe("Question Resolution scenarios", function () {
            let ctf: MockConditionalTokens;
            let optimisticOracle: MockContract;
            let testRewardToken: TestERC20;
            let umaCtfAdapter: UmaCtfAdapter;
            let questionID: string;
            let bond: BigNumber;
            let conditionID: string;

            beforeEach(async function () {
                const deployment = await setup();
                ctf = deployment.ctf;
                optimisticOracle = deployment.optimisticOracle;
                testRewardToken = deployment.testRewardToken;
                umaCtfAdapter = deployment.umaCtfAdapter;

                await optimisticOracle.mock.hasPrice.returns(true);

                bond = ethers.utils.parseEther("10000.0");

                // initialize question
                questionID = await initializeQuestion(
                    umaCtfAdapter,
                    QUESTION_TITLE,
                    DESC,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    bond,
                );

                conditionID = await ctf.getConditionId(umaCtfAdapter.address, questionID, 2);
                const oneEther = ethers.utils.parseEther("1");

                // Mocks on optimistic oracle
                await optimisticOracle.mock.settleAndGetPrice.returns(oneEther);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
            });

            it("readyToResolve returns true if price data is available from the OO", async function () {
                // Non existent questionID
                expect(await umaCtfAdapter.readyToResolve(HashZero)).eq(false);
                await optimisticOracle.mock.hasPrice.returns(true);
                expect(await umaCtfAdapter.readyToResolve(questionID)).eq(true);
            });

            it("should correctly resolve a question if it is readyToResolve", async function () {
                // Mocks to ensure readyToResolve
                await optimisticOracle.mock.hasPrice.returns(true);

                // Verify events emitted
                expect(await umaCtfAdapter.connect(this.signers.tester).resolve(questionID))
                    .to.emit(ctf, "ConditionResolution")
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, 2, [1, 0])
                    .and.to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, false, [1, 0]);
            });

            // Resolve revert cases
            it("resolve reverts if question is not initialized", async function () {
                await expect(umaCtfAdapter.connect(this.signers.admin).resolve(HashZero)).to.be.revertedWith(
                    "Adapter/not-ready-to-resolve",
                );
            });

            it("resolve reverts if price data is not available for the question", async function () {
                await optimisticOracle.mock.hasPrice.returns(false);
                await expect(umaCtfAdapter.connect(this.signers.admin).resolve(questionID)).to.be.revertedWith(
                    "Adapter/not-ready-to-resolve",
                );
            });

            it("resolve reverts if question is paused", async function () {
                await umaCtfAdapter.connect(this.signers.admin).pauseQuestion(questionID);
                await expect(umaCtfAdapter.resolve(questionID)).to.be.revertedWith("Adapter/paused");
            });

            it("resolve reverts if OO returns malformed data", async function () {
                // Mock Optimistic Oracle returns invalid data
                await optimisticOracle.mock.settleAndGetPrice.returns(BigNumber.from(21233));
                await expect(umaCtfAdapter.resolve(questionID)).to.be.revertedWith("Adapter/invalid-resolution-data");
            });

            it("resolve reverts if question is already resolved", async function () {
                await (await umaCtfAdapter.connect(this.signers.admin).resolve(questionID)).wait();
                await expect(umaCtfAdapter.connect(this.signers.admin).resolve(questionID)).to.be.revertedWith(
                    "Adapter/already-resolved",
                );
            });

            it("should revert calling expected payouts if the question is not initialized", async function () {
                await expect(umaCtfAdapter.getExpectedPayouts(HashZero)).to.be.revertedWith("Adapter/not-initialized");
            });

            it("should revert calling expected payouts if the price does not exist on the OO", async function () {
                await optimisticOracle.mock.hasPrice.returns(false);
                await expect(umaCtfAdapter.getExpectedPayouts(questionID)).to.be.revertedWith(
                    "Adapter/price-unavailable",
                );
            });

            it("should return expected payouts correctly if the price exists on the OO", async function () {
                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                await optimisticOracle.mock.settleAndGetPrice.returns(ONE_ETHER);

                // Get expected payouts
                const expectedPayouts = await (
                    await umaCtfAdapter.getExpectedPayouts(questionID)
                ).map(el => el.toString());
                expect(expectedPayouts.length).to.eq(2);
                expect(expectedPayouts[0]).to.eq("1");
                expect(expectedPayouts[1]).to.eq("0");
            });

            // Resolving with diferent payouts
            it("should correctly report [1,0] when YES", async function () {
                expect(await umaCtfAdapter.resolve(questionID))
                    .to.emit(ctf, "ConditionResolution")
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, 2, [1, 0])
                    .and.to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, 1, [1, 0]);
            });

            it("should correctly report [0,1] when NO", async function () {
                await optimisticOracle.mock.settleAndGetPrice.returns(0);

                expect(await umaCtfAdapter.resolve(questionID))
                    .to.emit(ctf, "ConditionResolution")
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, 2, [0, 1])
                    .and.to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, 0, [0, 1]);
            });

            it("should correctly report [1,1] when UNKNOWN", async function () {
                await optimisticOracle.mock.settleAndGetPrice.returns(ethers.utils.parseEther("0.5"));

                expect(await umaCtfAdapter.resolve(questionID))
                    .to.emit(ctf, "ConditionResolution")
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, 2, [1, 1])
                    .and.to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, 0.5, [1, 1]);
            });

            it("should revert if flagged by non-admin", async function () {
                await expect(umaCtfAdapter.connect(this.signers.tester).flag(questionID)).to.be.revertedWith(
                    "Adapter/not-authorized",
                );
            });

            it("should revert if flagging a non-initialized question", async function () {
                await expect(umaCtfAdapter.flag(HashZero)).to.be.revertedWith("Adapter/not-initialized");
            });

            it("should allow emergency resolve by the admin", async function () {
                // Verify admin resolution timestamp was set to zero upon question initialization
                const questionData = await umaCtfAdapter.questions(questionID);

                expect(await questionData.adminResolutionTimestamp).to.eq(0);

                // Verify emergency resolution flag check returns false
                expect(await umaCtfAdapter.isFlagged(questionID)).eq(false);

                // flag question for resolution
                expect(await umaCtfAdapter.flag(questionID))
                    .to.emit(umaCtfAdapter, "QuestionFlagged")
                    .withArgs(questionID);

                // flag question for resolution should fail second time
                expect(umaCtfAdapter.flag(questionID)).to.be.revertedWith("Adapter/already-flagged");

                // Verify admin resolution timestamp was set
                expect((await umaCtfAdapter.questions(questionID)).adminResolutionTimestamp).gt(0);

                // Verify emergency resolution flag check returns true
                expect(await umaCtfAdapter.isFlagged(questionID)).eq(true);

                // fast forward the chain to after the emergencySafetyPeriod
                await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

                // YES conditional payout
                const payouts = [1, 0];
                expect(await umaCtfAdapter.emergencyResolve(questionID, payouts))
                    .to.emit(umaCtfAdapter, "QuestionEmergencyResolved")
                    .withArgs(questionID, payouts);

                // Verify resolved flag on the QuestionData struct has been updated
                expect((await umaCtfAdapter.questions(questionID)).resolved).eq(true);
            });

            it("should allow emergency resolve even if the question is paused", async function () {
                // Pause question
                await umaCtfAdapter.connect(this.signers.admin).pauseQuestion(questionID);

                // flag for emergency resolution
                await umaCtfAdapter.flag(questionID);

                // fast forward the chain to after the emergencySafetyPeriod
                await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

                // YES conditional payout
                const payouts = [1, 0];
                expect(await umaCtfAdapter.emergencyResolve(questionID, payouts))
                    .to.emit(umaCtfAdapter, "QuestionEmergencyResolved")
                    .withArgs(questionID, payouts);

                // Verify resolved flag on the QuestionData struct has been updated
                const questionData = await umaCtfAdapter.questions(questionID);
                expect(questionData.resolved).eq(true);
            });

            it("should revert if emergencyResolve is called before the question is flagged", async function () {
                // YES conditional payout
                const payouts = [1, 0];
                await expect(umaCtfAdapter.emergencyResolve(questionID, payouts)).to.be.revertedWith(
                    "Adapter/not-flagged",
                );
            });

            it("should revert if emergencyResolve is called before the safety period", async function () {
                // flag for emergency resolution
                await umaCtfAdapter.flag(questionID);

                // YES conditional payout
                const payouts = [1, 0];
                await expect(umaCtfAdapter.emergencyResolve(questionID, payouts)).to.be.revertedWith(
                    "Adapter/safety-period-not-passed",
                );
            });

            it("should revert if emergencyResolve is called with invalid payout", async function () {
                // flag for emergency resolution
                await umaCtfAdapter.flag(questionID);

                // fast forward the chain to post-emergencySafetyPeriod
                await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

                // invalid conditional payout
                const nonBinaryPayoutVector = [0, 0, 0, 0, 1, 2, 3, 4, 5];
                await expect(umaCtfAdapter.emergencyResolve(questionID, nonBinaryPayoutVector)).to.be.revertedWith(
                    "Adapter/non-binary-payouts",
                );
            });

            it("should revert if emergencyResolve is called from a non-admin", async function () {
                await expect(
                    umaCtfAdapter.connect(this.signers.tester).emergencyResolve(questionID, [1, 0]),
                ).to.be.revertedWith("Adapter/not-authorized");
            });

            it("should revert if emergencyResolve is called on a non-initialized questionID", async function () {
                await expect(umaCtfAdapter.emergencyResolve(HashZero, [1, 0])).to.be.revertedWith(
                    "Adapter/not-initialized",
                );
            });
        });

        describe("Invalid proposal scenarios", function () {
            let optimisticOracle: MockContract;
            let testRewardToken: TestERC20;
            let umaCtfAdapter: UmaCtfAdapter;
            let ancillaryData: Uint8Array;
            let questionID: string;
            let reward: BigNumber;

            before(async function () {
                const deployment = await setup();
                optimisticOracle = deployment.optimisticOracle;
                testRewardToken = deployment.testRewardToken;
                umaCtfAdapter = deployment.umaCtfAdapter;
                reward = ethers.utils.parseEther("10.0");
                const bond = ethers.utils.parseEther("1000.0");
                ancillaryData = createAncillaryData(
                    ethers.utils.randomBytes(5).toString(),
                    ethers.utils.randomBytes(10).toString(),
                );

                await (
                    await umaCtfAdapter.initializeQuestion(ancillaryData, testRewardToken.address, reward, bond)
                ).wait();

                questionID = await umaCtfAdapter.getQuestionID(ancillaryData);
            });

            it("reverts if a non-OO address calls priceDisputed", async function () {
                await expect(
                    umaCtfAdapter
                        .connect(this.signers.tester)
                        .priceDisputed(HashZero, 0, ethers.utils.randomBytes(10), 10),
                ).to.be.revertedWith("Adapter/not-oo");
            });

            it("sends out a new price request if an invalid proposal is proposed", async function () {
                // Check original question parameters
                const questionData = await umaCtfAdapter.questions(questionID);
                const originalRequestTimestamp = questionData.requestTimestamp;
                expect(originalRequestTimestamp).gt(0);

                await optimisticOracle.mock.hasPrice.returns(false);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                // Verify `readyToResolve` returns false on startup, since no proposal has been put forward
                expect(await umaCtfAdapter.readyToResolve(questionID)).to.eq(false);

                // Fast forward an hour into the future
                await hardhatIncreaseTime(3600);

                // Mock that an OO dispute has occured, refunding the original price request and...
                await (
                    await testRewardToken.connect(this.signers.admin).transfer(umaCtfAdapter.address, reward)
                ).wait();

                // ...executing the priceDisputed callback on the Adapter
                // Verify that the callback *resets* the question, sending out a new price request to the OO,
                // and discarding the original price request
                const ooSigner = await getSignerForAddress(optimisticOracle.address);
                expect(
                    await umaCtfAdapter.connect(ooSigner).priceDisputed(
                        "0x5945535f4f525f4e4f5f51554552590000000000000000000000000000000000", // YES or no identifer
                        originalRequestTimestamp,
                        ancillaryData,
                        reward,
                    ),
                )
                    .to.emit(testRewardToken, "Transfer") // Transfer refunded reward from Adapter to OO
                    .withArgs(umaCtfAdapter.address, optimisticOracle.address, reward)
                    .to.emit(umaCtfAdapter, "QuestionReset") // Reset the question
                    .withArgs(questionID);

                // Verify chain state after resetting the question
                const questionDataUpdated = await umaCtfAdapter.questions(questionID);

                // Request timestamp will be updated
                const requestTimestamp = questionDataUpdated.requestTimestamp;
                expect(requestTimestamp).to.be.gt(originalRequestTimestamp);

                // But all other question data is the same
                expect(questionData.creator).to.be.eq(questionDataUpdated.creator);
                expect(questionData.ancillaryData).to.be.eq(questionDataUpdated.ancillaryData);
                expect(questionData.reward).to.be.eq(questionDataUpdated.reward);
                expect(questionData.rewardToken).to.be.eq(questionDataUpdated.rewardToken);
            });

            it("should correctly resolve the question after the new price request is sent", async function () {
                await optimisticOracle.mock.hasPrice.returns(false);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());

                // Verify `readyToResolve` returns false on startup, since no proposal has been put forward
                expect(await umaCtfAdapter.readyToResolve(questionID)).to.eq(false);

                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                await optimisticOracle.mock.settleAndGetPrice.returns(ONE_ETHER);

                // Verify QuestionResolved emitted
                expect(await umaCtfAdapter.resolve(questionID))
                    .to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, 1, [1, 0]);
            });
        });

        describe("Ancillary data update scenarios", function () {
            let testRewardToken: TestERC20;
            let umaCtfAdapter: UmaCtfAdapter;
            let questionID: string;

            before(async function () {
                const deployment = await setup();
                testRewardToken = deployment.testRewardToken;
                umaCtfAdapter = deployment.umaCtfAdapter;

                // Initialize the question
                questionID = await initializeQuestion(
                    umaCtfAdapter,
                    ethers.utils.randomBytes(5).toString(),
                    ethers.utils.randomBytes(10).toString(),
                    testRewardToken.address,
                    ethers.utils.parseEther("10.0"),
                    ethers.utils.parseEther("1000.0"),
                );
            });

            it("posts an ancillary data update for a questionID", async function () {
                const newAncillaryData = ethers.utils.randomBytes(20);

                // Post an update
                expect(await umaCtfAdapter.connect(this.signers.admin).postUpdate(questionID, newAncillaryData))
                    .to.emit(umaCtfAdapter, "AncillaryDataUpdated")
                    .withArgs(questionID, this.signers.admin.address, newAncillaryData);

                // Verify chain state
                const updates = await umaCtfAdapter.getUpdates(questionID, this.signers.admin.address);
                expect(updates.length).to.eq(1);
                expect(updates[0].update).to.eq(ethers.utils.hexlify(newAncillaryData));

                // Verify result when fetching a non-existent questionID
                const result = await umaCtfAdapter.getUpdates(HashZero, ethers.Wallet.createRandom().address);
                expect(result.length).to.eq(0);
            });

            it("successfully retrieves the latest ancillary data update", async function () {
                // Verify chain state
                const update = await umaCtfAdapter.getLatestUpdate(questionID, this.signers.admin.address);
                expect(update.update).to.not.eq(null);

                // Verify result when fetching a non-existent questionID
                const nonExistentUpdate = await umaCtfAdapter.getLatestUpdate(HashZero, this.signers.admin.address);
                expect(nonExistentUpdate.timestamp).to.eq(0);
                expect(nonExistentUpdate.update).to.eq("0x");
            });
        });
    });
});
