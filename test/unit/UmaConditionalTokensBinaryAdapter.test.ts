import hre, { deployments, ethers } from "hardhat";
import { HashZero } from "@ethersproject/constants";
import { expect } from "chai";
import { MockContract } from "@ethereum-waffle/mock-contract";
import { BigNumber } from "ethers";
import { Griefer, MockConditionalTokens, TestERC20, UmaCtfAdapter } from "../../typechain";
import {
    createQuestionID,
    deploy,
    deployMock,
    createAncillaryData,
    hardhatIncreaseTime,
    initializeQuestion,
    getMockRequest,
    createRandomQuestionID,
} from "../helpers";
import { DESC, QUESTION_TITLE, emergencySafetyPeriod, MAX_ANCILLARY_DATA } from "./constants";

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

    // Mint a million TST to admin
    await (await testRewardToken.mint(admin.address, BigNumber.from(ethers.utils.parseEther("1000000")))).wait();

    const optimisticOracle: MockContract = await deployMock("OptimisticOracleV2Interface");
    await optimisticOracle.mock.requestPrice.returns(0);
    await optimisticOracle.mock.settleAndGetPrice.returns(ethers.constants.One);
    await optimisticOracle.mock.setBond.returns(ethers.constants.One);
    await optimisticOracle.mock.setEventBased.returns();
    await optimisticOracle.mock.getRequest.returns(getMockRequest());

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
        describe("Setup", function () {
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
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = 0;
                const proposalBond = 0;
                const outcomeSlotCount = 2;
                const conditionID = await ctf.getConditionId(umaCtfAdapter.address, questionID, outcomeSlotCount);

                // Initializing a question does the following:
                // 1. Stores the question parameters in Adapter storage,
                // 2. Prepares the question on the CTF
                // 3. Requests a price from the OO, paying the request reward
                expect(
                    await umaCtfAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        testRewardToken.address,
                        reward,
                        proposalBond,
                    ),
                )
                    .to.emit(umaCtfAdapter, "QuestionInitialized")
                    .and.to.emit(ctf, "ConditionPreparation")
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, outcomeSlotCount);

                const returnedQuestionData = await umaCtfAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.requestTimestamp).gt(0);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(0);

                // ensure paused defaults to false
                expect(returnedQuestionData.paused).eq(false);
                expect(returnedQuestionData.settled).eq(0);
            });

            it("correctly initializes a question with non-zero reward and bond", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");
                const outcomeSlotCount = 2;
                const conditionID = await ctf.getConditionId(umaCtfAdapter.address, questionID, outcomeSlotCount);
                const initializerBalance = await testRewardToken.balanceOf(this.signers.admin.address);

                expect(
                    await umaCtfAdapter
                        .connect(this.signers.admin)
                        .initializeQuestion(questionID, ancillaryData, testRewardToken.address, reward, proposalBond),
                )
                    .to.emit(umaCtfAdapter, "QuestionInitialized") // Question gets initialized
                    .and.to.emit(ctf, "ConditionPreparation") // Condition gets prepared on the CTF
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, outcomeSlotCount)
                    .and.to.emit(testRewardToken, "Transfer") // Transfer reward from caller to the Adapter
                    .withArgs(this.signers.admin.address, umaCtfAdapter.address, reward);

                const returnedQuestionData = await umaCtfAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
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
                const questionID = createRandomQuestionID();
                const ancillaryData = ethers.utils.randomBytes(10);

                await umaCtfAdapter.initializeQuestion(questionID, ancillaryData, testRewardToken.address, 0, 0);

                // reinitialize the same questionID
                await expect(
                    umaCtfAdapter.initializeQuestion(questionID, ancillaryData, testRewardToken.address, 0, 0),
                ).to.be.revertedWith("Adapter/already-initialized");
            });

            it("should revert if the initializer does not have reward tokens or allowance", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");

                await expect(
                    umaCtfAdapter
                        .connect(this.signers.tester)
                        .initializeQuestion(
                            questionID,
                            ancillaryDataHexlified,
                            testRewardToken.address,
                            reward,
                            proposalBond,
                        ),
                ).to.be.revertedWith("TransferHelper/STF");
            });

            it("should revert when initializing with an unsupported reward token", async function () {
                const questionID = createRandomQuestionID();
                const ancillaryData = ethers.utils.randomBytes(10);

                // Deploy a new token
                const unsupportedToken: TestERC20 = await deploy<TestERC20>("TestERC20", {
                    args: ["", ""],
                });

                await whitelist.mock.isOnWhitelist.withArgs(unsupportedToken.address).returns(false);

                // Reverts since the token isn't supported
                await expect(
                    umaCtfAdapter.initializeQuestion(questionID, ancillaryData, unsupportedToken.address, 0, 0),
                ).to.be.revertedWith("Adapter/unsupported-token");
            });

            it("should revert initialization if ancillary data is invalid", async function () {
                const questionID = createRandomQuestionID();

                // reverts if ancillary data length == 0 or > MAX_ANCILLARY_DATA
                await expect(
                    umaCtfAdapter.initializeQuestion(
                        questionID,
                        ethers.utils.randomBytes(0),
                        testRewardToken.address,
                        0,
                        0,
                    ),
                ).to.be.revertedWith("Adapter/invalid-ancillary-data");

                await expect(
                    umaCtfAdapter.initializeQuestion(
                        questionID,
                        ethers.utils.randomBytes(MAX_ANCILLARY_DATA + 1),
                        testRewardToken.address,
                        0,
                        0,
                    ),
                ).to.be.revertedWith("Adapter/invalid-ancillary-data");
            });

            // Settle tests
            it("readyToSettle returns true if price data is available from the OO", async function () {
                // Non existent questionID
                expect(await umaCtfAdapter.readyToSettle(HashZero)).eq(false);

                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");

                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    reward,
                    proposalBond,
                );

                await optimisticOracle.mock.hasPrice.returns(true);
                expect(await umaCtfAdapter.readyToSettle(questionID)).eq(true);
            });

            it("should correctly settle a question if it's readyToSettle", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");

                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    reward,
                    proposalBond,
                );

                // Mocks to ensure readyToSettle
                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                await optimisticOracle.mock.settleAndGetPrice.returns(1);

                // Verify QuestionSettled emitted
                expect(await umaCtfAdapter.connect(this.signers.tester).settle(questionID))
                    .to.emit(umaCtfAdapter, "QuestionSettled")
                    .withArgs(questionID, 1);

                // Verify settle block number != 0
                const questionData = await umaCtfAdapter.questions(questionID);
                expect(questionData.settled).to.not.eq(0);

                // Ready to settle should be false, after settling
                const readyToSettle = await umaCtfAdapter.readyToSettle(questionID);
                expect(readyToSettle).to.eq(false);
            });

            it("settle should revert if not readyToSettle", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();

                // Settle reverts if:
                // 1. QuestionID is not initialized
                const uninitQuestionID = HashZero;
                await expect(umaCtfAdapter.connect(this.signers.admin).settle(uninitQuestionID)).to.be.revertedWith(
                    "Adapter/not-ready-to-settle",
                );

                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                await optimisticOracle.mock.hasPrice.returns(false);
                // 2. If OO doesn't have the price available
                await expect(umaCtfAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter/not-ready-to-settle",
                );

                await optimisticOracle.mock.hasPrice.returns(true);

                // 3. If question is paused
                await (await umaCtfAdapter.connect(this.signers.admin).pauseQuestion(questionID)).wait();
                await expect(umaCtfAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter/paused",
                );

                await (await umaCtfAdapter.connect(this.signers.admin).unPauseQuestion(questionID)).wait();

                // 4. If question is already settled
                await (await umaCtfAdapter.connect(this.signers.admin).settle(questionID)).wait();
                await expect(umaCtfAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter/not-ready-to-settle",
                );
            });

            it("should revert calling expected payouts if the question is not initialized", async function () {
                await expect(umaCtfAdapter.getExpectedPayouts(HashZero)).to.be.revertedWith("Adapter/not-initialized");
            });

            it("should revert calling expected payouts if the question is not settled", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");

                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    reward,
                    proposalBond,
                );

                await expect(umaCtfAdapter.getExpectedPayouts(questionID)).to.be.revertedWith("Adapter/not-settled");
            });

            it("should return expected payouts correctly after the question is settled", async function () {
                // Initialize
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");

                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    reward,
                    proposalBond,
                );

                // Settle
                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                await optimisticOracle.mock.settleAndGetPrice.returns(1);
                await (await umaCtfAdapter.connect(this.signers.tester).settle(questionID)).wait();

                // Get expected payouts
                const expectedPayouts = await (
                    await umaCtfAdapter.getExpectedPayouts(questionID)
                ).map(el => el.toString());
                expect(expectedPayouts.length).to.eq(2);
                expect(expectedPayouts[0]).to.eq("1");
                expect(expectedPayouts[1]).to.eq("0");
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

            it("should disallow atomic settling and resolution", async function () {
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

                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.settleAndGetPrice.returns(1);

                const request = getMockRequest();
                await optimisticOracle.mock.getRequest.returns(request);

                const griefer: Griefer = await deploy<Griefer>("Griefer", {
                    args: [umaCtfAdapter.address],
                    connect: this.signers.admin,
                });

                await expect(griefer.settleAndReport(questionID)).to.be.revertedWith(
                    "Adapter/same-block-settle-report",
                );
            });

            it("should correctly update the question", async function () {
                const title = ethers.utils.randomBytes(10).toString();
                const desc = ethers.utils.randomBytes(20).toString();
                const ancillaryData = createAncillaryData(title, desc);

                const questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                const newReward = ethers.utils.parseEther("1");
                const newProposalBond = ethers.utils.parseEther("100.0");
                const callerBalance = await testRewardToken.balanceOf(this.signers.admin.address);

                // Updating a question will kick off a new price request to the Optimistic Oracle
                // Note: the original price request stil exists, but it will not be considered in the resolution of the question
                // Important to note that the reward for the original request will not be refunded
                expect(
                    await umaCtfAdapter
                        .connect(this.signers.admin)
                        .updateQuestion(questionID, ancillaryData, testRewardToken.address, newReward, newProposalBond),
                )
                    .to.emit(umaCtfAdapter, "QuestionUpdated") // Emit QuestionUpdated from the Adapter
                    .and.to.emit(testRewardToken, "Transfer") // Transfer the new price request reward from caller to the Adapter
                    .withArgs(this.signers.admin.address, umaCtfAdapter.address, newReward);

                const questionData = await umaCtfAdapter.questions(questionID);

                // Verify updated properties on the question data
                expect(questionData.reward.toString()).to.eq(newReward.toString());
                expect(questionData.proposalBond).to.eq(newProposalBond.toString());

                // Verify flags on the question data
                expect(questionData.settled).to.eq(0);
                expect(questionData.resolved).to.eq(false);
                expect(questionData.requestTimestamp).to.gt(0);
                expect(questionData.paused).to.eq(false);

                // Verify new price request was paid for
                const callerBalancePost = await testRewardToken.balanceOf(this.signers.admin.address);
                expect(callerBalance.sub(callerBalancePost).toString()).to.eq(newReward.toString());
            });

            it("update reverts if not initialized", async function () {
                await expect(
                    umaCtfAdapter
                        .connect(this.signers.admin)
                        .updateQuestion(
                            HashZero,
                            ethers.utils.randomBytes(10),
                            testRewardToken.address,
                            ethers.constants.Zero,
                            ethers.constants.Zero,
                        ),
                ).to.be.revertedWith("Adapter/not-initialized");
            });

            it("update revert scenarios", async function () {
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

                const newReward = ethers.utils.parseEther("1");
                const newProposalBond = ethers.utils.parseEther("100.0");

                // Update reverts if not an admin
                await expect(
                    umaCtfAdapter
                        .connect(this.signers.tester)
                        .updateQuestion(
                            questionID,
                            ethers.utils.randomBytes(10),
                            testRewardToken.address,
                            newReward,
                            newProposalBond,
                        ),
                ).to.be.revertedWith("Adapter/not-authorized");

                // reverts if unsupported token
                await whitelist.mock.isOnWhitelist.returns(false);
                await expect(
                    umaCtfAdapter
                        .connect(this.signers.admin)
                        .updateQuestion(
                            questionID,
                            ethers.utils.randomBytes(10),
                            ethers.Wallet.createRandom().address,
                            newReward,
                            newProposalBond,
                        ),
                ).to.be.revertedWith("Adapter/unsupported-token");

                await whitelist.mock.isOnWhitelist.returns(true);

                // reverts if invalid ancillary data invalid
                await expect(
                    umaCtfAdapter
                        .connect(this.signers.admin)
                        .updateQuestion(
                            questionID,
                            ethers.utils.randomBytes(0),
                            testRewardToken.address,
                            newReward,
                            newProposalBond,
                        ),
                ).to.be.revertedWith("Adapter/invalid-ancillary-data");

                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                await optimisticOracle.mock.settleAndGetPrice.returns(1);
                await (await umaCtfAdapter.settle(questionID)).wait();

                // reverts if the question is already settled
                await expect(
                    umaCtfAdapter
                        .connect(this.signers.admin)
                        .updateQuestion(
                            questionID,
                            ethers.utils.randomBytes(10),
                            testRewardToken.address,
                            newReward,
                            newProposalBond,
                        ),
                ).to.be.revertedWith("Adapter/already-settled");
            });
        });

        describe("Resolution scenarios", function () {
            let ctf: MockConditionalTokens;
            let optimisticOracle: MockContract;
            let testRewardToken: TestERC20;
            let umaCtfAdapter: UmaCtfAdapter;
            let questionID: string;
            let bond: BigNumber;

            beforeEach(async function () {
                const deployment = await setup();
                ctf = deployment.ctf;
                optimisticOracle = deployment.optimisticOracle;
                testRewardToken = deployment.testRewardToken;
                umaCtfAdapter = deployment.umaCtfAdapter;

                await optimisticOracle.mock.hasPrice.returns(true);

                questionID = createQuestionID(QUESTION_TITLE, DESC);
                bond = ethers.utils.parseEther("10000.0");

                // initialize question
                await initializeQuestion(
                    umaCtfAdapter,
                    QUESTION_TITLE,
                    DESC,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    bond,
                );

                // settle
                await optimisticOracle.mock.settleAndGetPrice.returns(1);
                const request = getMockRequest();
                await optimisticOracle.mock.getRequest.returns(request);
                await (await umaCtfAdapter.settle(questionID)).wait();
            });

            it("readyToSettle returns false if question is already resolved", async function () {
                await (await umaCtfAdapter.reportPayouts(questionID)).wait();
                expect(await umaCtfAdapter.readyToSettle(questionID)).to.be.eq(false);
            });

            it("should correctly report [1,0] when YES", async function () {
                const conditionID = await ctf.getConditionId(umaCtfAdapter.address, questionID, 2);

                expect(await umaCtfAdapter.reportPayouts(questionID))
                    .to.emit(ctf, "ConditionResolution")
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, 2, [1, 0])
                    .and.to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, false);
            });

            it("should correctly report [0,1] when NO", async function () {
                const conditionID = await ctf.getConditionId(umaCtfAdapter.address, questionID, 2);
                const request = getMockRequest();
                request.resolvedPrice = ethers.constants.Zero;
                await optimisticOracle.mock.getRequest.returns(request);

                expect(await umaCtfAdapter.reportPayouts(questionID))
                    .to.emit(ctf, "ConditionResolution")
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, 2, [0, 1])
                    .and.to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, false);
            });

            it("should correctly report [1,1] when UNKNOWN", async function () {
                const conditionID = await ctf.getConditionId(umaCtfAdapter.address, questionID, 2);

                const request = getMockRequest();
                request.resolvedPrice = ethers.utils.parseEther("0.5");
                await optimisticOracle.mock.getRequest.returns(request);

                expect(await umaCtfAdapter.reportPayouts(questionID))
                    .to.emit(ctf, "ConditionResolution")
                    .withArgs(conditionID, umaCtfAdapter.address, questionID, 2, [1, 1])
                    .and.to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, false);
            });

            it("reportPayouts reverts if the question has been previously resolved", async function () {
                await (await umaCtfAdapter.reportPayouts(questionID)).wait();

                // Attempt to report payouts again
                await expect(umaCtfAdapter.reportPayouts(questionID)).to.be.revertedWith("Adapter/already-resolved");
            });

            it("reportPayouts reverts if OO returns malformed data", async function () {
                // Mock Optimistic Oracle returns invalid data
                const request = getMockRequest();
                request.resolvedPrice = BigNumber.from(21233);
                await optimisticOracle.mock.getRequest.returns(request);

                await expect(umaCtfAdapter.reportPayouts(questionID)).to.be.revertedWith(
                    "Adapter/invalid-resolution-data",
                );
            });

            it("reportPayouts reverts if question is paused", async function () {
                await umaCtfAdapter.connect(this.signers.admin).pauseQuestion(questionID);

                await expect(umaCtfAdapter.reportPayouts(questionID)).to.be.revertedWith("Adapter/paused");
            });

            it("should allow emergency reporting by the admin", async function () {
                // Verify admin resolution timestamp was set to zero upon question initialization
                const questionData = await umaCtfAdapter.questions(questionID);

                expect(await questionData.adminResolutionTimestamp).to.eq(0);

                // Verify emergency resolution flag check returns false
                expect(await umaCtfAdapter.isQuestionFlaggedForEmergencyResolution(questionID)).eq(false);

                // flag question for resolution
                expect(await umaCtfAdapter.flagQuestionForEmergencyResolution(questionID))
                    .to.emit(umaCtfAdapter, "QuestionFlaggedForAdminResolution")
                    .withArgs(questionID);

                // flag question for resolution should fail second time
                expect(umaCtfAdapter.flagQuestionForEmergencyResolution(questionID)).to.be.revertedWith(
                    "Adapter/already-flagged",
                );

                // Verify admin resolution timestamp was set
                expect((await umaCtfAdapter.questions(questionID)).adminResolutionTimestamp).gt(0);

                // Verify emergency resolution flag check returns true
                expect(await umaCtfAdapter.isQuestionFlaggedForEmergencyResolution(questionID)).eq(true);

                // fast forward the chain to after the emergencySafetyPeriod
                await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

                // YES conditional payout
                const payouts = [1, 0];
                expect(await umaCtfAdapter.emergencyReportPayouts(questionID, payouts))
                    .to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, true);

                // Verify resolved flag on the QuestionData struct has been updated
                expect((await umaCtfAdapter.questions(questionID)).resolved).eq(true);
            });

            it("should allow emergency reporting even if the question is paused", async function () {
                // Pause question
                await umaCtfAdapter.connect(this.signers.admin).pauseQuestion(questionID);

                // flag for emergency resolution
                await umaCtfAdapter.flagQuestionForEmergencyResolution(questionID);

                // fast forward the chain to after the emergencySafetyPeriod
                await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

                // YES conditional payout
                const payouts = [1, 0];
                expect(await umaCtfAdapter.emergencyReportPayouts(questionID, payouts))
                    .to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, true);

                // Verify resolved flag on the QuestionData struct has been updated
                const questionData = await umaCtfAdapter.questions(questionID);
                expect(questionData.resolved).eq(true);
            });

            it("should revert if emergencyReport is called before the question is flagged", async function () {
                // YES conditional payout
                const payouts = [1, 0];
                await expect(umaCtfAdapter.emergencyReportPayouts(questionID, payouts)).to.be.revertedWith(
                    "Adapter/not-flagged",
                );
            });

            it("should revert if emergencyReport is called before the safety period", async function () {
                // flag for emergency resolution
                await umaCtfAdapter.flagQuestionForEmergencyResolution(questionID);

                // YES conditional payout
                const payouts = [1, 0];
                await expect(umaCtfAdapter.emergencyReportPayouts(questionID, payouts)).to.be.revertedWith(
                    "Adapter/safety-period-not-passed",
                );
            });

            it("should revert if emergencyReport is called with invalid payout", async function () {
                // flag for emergency resolution
                await umaCtfAdapter.flagQuestionForEmergencyResolution(questionID);

                // fast forward the chain to post-emergencySafetyPeriod
                await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

                // invalid conditional payout
                const nonBinaryPayoutVector = [0, 0, 0, 0, 1, 2, 3, 4, 5];
                await expect(
                    umaCtfAdapter.emergencyReportPayouts(questionID, nonBinaryPayoutVector),
                ).to.be.revertedWith("Adapter/non-binary-payouts");
            });

            it("should revert if emergencyReport is called from a non-admin", async function () {
                await expect(
                    umaCtfAdapter.connect(this.signers.tester).emergencyReportPayouts(questionID, [1, 0]),
                ).to.be.revertedWith("Adapter/not-authorized");
            });
        });

        describe("Invalid proposal scenarios", function () {
            let optimisticOracle: MockContract;
            let testRewardToken: TestERC20;
            let umaCtfAdapter: UmaCtfAdapter;
            let questionID: string;
            let reward: BigNumber;

            before(async function () {
                const deployment = await setup();
                optimisticOracle = deployment.optimisticOracle;
                testRewardToken = deployment.testRewardToken;
                umaCtfAdapter = deployment.umaCtfAdapter;
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                reward = ethers.utils.parseEther("10.0");
                const bond = ethers.utils.parseEther("1000.0");

                // Initialize the question
                questionID = await initializeQuestion(
                    umaCtfAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    reward,
                    bond,
                );
            });

            it("sends out a new price request if an invalid proposal is proposed", async function () {
                // Check original question parameters
                const questionData = await umaCtfAdapter.questions(questionID);
                const originalRequestTimestamp = questionData.requestTimestamp;
                expect(originalRequestTimestamp).gt(0);

                await optimisticOracle.mock.hasPrice.returns(false);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                // Verify `readyToSettle` returns false on startup, since no proposal has been put forward
                expect(await umaCtfAdapter.readyToSettle(questionID)).to.eq(false);

                // Fast forward an hour into the future
                await hardhatIncreaseTime(3600);

                // Mock that an invalid proposal is proposed and disputed by the DVM, refunding the Adapter with the reward
                const disputed = getMockRequest();
                disputed.disputer = ethers.Wallet.createRandom().address;
                await optimisticOracle.mock.hasPrice.returns(false);
                await optimisticOracle.mock.getRequest.returns(disputed);
                await (await testRewardToken.transfer(umaCtfAdapter.address, reward)).wait();

                // Verify that `readyToSettle` returns true since there is now a disputed proposal
                expect(await umaCtfAdapter.readyToSettle(questionID)).to.eq(true);

                // Verify that calling `settle` on a question with a disputed proposal *resets* the question,
                // sending out a new price request to the OO and discarding the original price request
                expect(await umaCtfAdapter.settle(questionID))
                    // Question is reset by the adapter, sending out a new price request with a new timestamp
                    .to.emit(umaCtfAdapter, "QuestionReset")
                    .withArgs(questionID);

                // Note that there's no need to transfer the reward from caller to the Adapter
                // since the adapter should already have the reward

                // Verify chain state after resetting the question
                const questionDataUpdated = await umaCtfAdapter.questions(questionID);

                // Request timestamp will be updated
                const requestTimestamp = questionDataUpdated.requestTimestamp;
                expect(requestTimestamp).to.be.gt(originalRequestTimestamp);

                // But all other question data is the same
                expect(questionData.ancillaryData).to.be.eq(questionDataUpdated.ancillaryData);
                expect(questionData.reward).to.be.eq(questionDataUpdated.reward);
                expect(questionData.rewardToken).to.be.eq(questionDataUpdated.rewardToken);
            });

            it("should correctly settle the question after a new price request is sent", async function () {
                await optimisticOracle.mock.hasPrice.returns(false);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());

                // Verify `readyToSettle` returns false on startup, since no proposal has been put forward
                expect(await umaCtfAdapter.readyToSettle(questionID)).to.eq(false);

                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                await optimisticOracle.mock.settleAndGetPrice.returns(1);

                // Verify QuestionSettled emitted
                expect(await umaCtfAdapter.settle(questionID))
                    .to.emit(umaCtfAdapter, "QuestionSettled")
                    .withArgs(questionID, 1);

                // Verify settle block number != 0
                const questionData = await umaCtfAdapter.questions(questionID);
                expect(questionData.settled).to.not.eq(0);

                // Ready to settle should be false, after settling
                const readyToSettle = await umaCtfAdapter.readyToSettle(questionID);
                expect(readyToSettle).to.eq(false);
            });

            it("should report payouts correctly", async function () {
                expect(await umaCtfAdapter.reportPayouts(questionID))
                    .to.emit(umaCtfAdapter, "QuestionResolved")
                    .withArgs(questionID, false);

                const questionData = await umaCtfAdapter.questions(questionID);
                expect(await questionData.resolved).eq(true);
            });
        });
    });
});
