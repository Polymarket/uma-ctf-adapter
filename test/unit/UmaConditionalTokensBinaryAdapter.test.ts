import hre, { deployments, ethers } from "hardhat";
import { HashZero } from "@ethersproject/constants";
import { Contract } from "@ethersproject/contracts";
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
    prepareCondition,
    initializeQuestion,
    takeSnapshot,
    revertToSnapshot,
    getMockRequest,
    createRandomQuestionID,
} from "../helpers";
import { DESC, IGNORE_PRICE, QUESTION_TITLE, emergencySafetyPeriod, MAX_ANCILLARY_DATA } from "./constants";
import { TASK_COMPILE_SOLIDITY_COMPILE } from "hardhat/builtin-tasks/task-names";

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

    const whitelist: MockContract = await deployMock("AddressWhitelistInterface");
    await whitelist.mock.isOnWhitelist.returns(true);

    const finderContract: MockContract = await deployMock("FinderInterface");

    await finderContract.mock.getImplementationAddress
        .withArgs(ethers.utils.formatBytes32String("OptimisticOracleV2"))
        .returns(optimisticOracle.address);

    await finderContract.mock.getImplementationAddress
        .withArgs(ethers.utils.formatBytes32String("CollateralWhitelist"))
        .returns(whitelist.address);

    const umaBinaryAdapter: UmaCtfAdapter = await deploy<UmaCtfAdapter>("UmaCtfAdapter", {
        args: [ctf.address, finderContract.address],
        connect: admin,
    });

    // Approve TST token with admin signer as owner and adapter as spender
    await (await testRewardToken.connect(admin).approve(umaBinaryAdapter.address, ethers.constants.MaxUint256)).wait();

    return {
        ctf,
        finderContract,
        optimisticOracle,
        whitelist,
        testRewardToken,
        umaBinaryAdapter,
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
        describe("setup", function () {
            let ctf: MockConditionalTokens;
            let optimisticOracle: MockContract;
            let umaBinaryAdapter: UmaCtfAdapter;

            before(async function () {
                const deployment = await setup();
                ctf = deployment.ctf;
                optimisticOracle = deployment.optimisticOracle;
                umaBinaryAdapter = deployment.umaBinaryAdapter;
            });

            it("correctly authorizes users", async function () {
                expect(await umaBinaryAdapter.wards(this.signers.admin.address)).eq(1);
                expect(await umaBinaryAdapter.wards(this.signers.tester.address)).eq(0);

                // Authorize the user
                expect(await umaBinaryAdapter.rely(this.signers.tester.address))
                    .to.emit(umaBinaryAdapter, "AuthorizedUser")
                    .withArgs(this.signers.tester.address);

                // Deauthorize the user
                expect(await umaBinaryAdapter.deny(this.signers.tester.address))
                    .to.emit(umaBinaryAdapter, "DeauthorizedUser")
                    .withArgs(this.signers.tester.address);

                // Attempt to authorize without being authorized
                await expect(
                    umaBinaryAdapter.connect(this.signers.tester).rely(this.signers.tester.address),
                ).to.be.revertedWith("Adapter/not-authorized");
            });

            it("correctly sets up contracts", async function () {
                const returnedCtf = await umaBinaryAdapter.ctf();
                expect(ctf.address).eq(returnedCtf);

                const returnedOptimisticOracle = await umaBinaryAdapter.optimisticOracle();
                expect(optimisticOracle.address).eq(returnedOptimisticOracle);
            });
        });

        describe("Question scenarios", function () {
            let ctf: MockConditionalTokens;
            let optimisticOracle: MockContract;
            let whitelist: MockContract;
            let testRewardToken: TestERC20;
            let umaBinaryAdapter: UmaCtfAdapter;

            before(async function () {
                const deployment = await setup();
                ctf = deployment.ctf;
                optimisticOracle = deployment.optimisticOracle;
                whitelist = deployment.whitelist;
                testRewardToken = deployment.testRewardToken;
                umaBinaryAdapter = deployment.umaBinaryAdapter;
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
                const conditionID = await ctf.getConditionId(umaBinaryAdapter.address, questionID, outcomeSlotCount);

                // Initializing a question does the following:
                // 1. Stores the question parameters in Adapter storage,
                // 2. Prepares the question on the CTF
                // 3. Requests a price from the OO, paying the request reward
                expect(
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        testRewardToken.address,
                        reward,
                        proposalBond,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized")
                    .and.to.emit(ctf, "ConditionPreparation")
                    .withArgs(conditionID, umaBinaryAdapter.address, questionID, outcomeSlotCount);

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

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
                const conditionID = await ctf.getConditionId(umaBinaryAdapter.address, questionID, outcomeSlotCount);
                const initializerBalance = await testRewardToken.balanceOf(this.signers.admin.address);

                expect(
                    await umaBinaryAdapter
                        .connect(this.signers.admin)
                        .initializeQuestion(questionID, ancillaryData, testRewardToken.address, reward, proposalBond),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized") // Question gets initialized
                    .and.to.emit(ctf, "ConditionPreparation") // Condition gets prepared on the CTF
                    .withArgs(conditionID, umaBinaryAdapter.address, questionID, outcomeSlotCount)
                    .and.to.emit(testRewardToken, "Transfer") // Transfer reward from caller to the Adapter
                    .withArgs(this.signers.admin.address, umaBinaryAdapter.address, reward);

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.requestTimestamp).gt(0);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(reward);
                expect(returnedQuestionData.proposalBond).eq(proposalBond);

                // Verify reward token allowance from Adapter with OO as spender
                const rewardTokenAllowance: BigNumber = await testRewardToken.allowance(
                    umaBinaryAdapter.address,
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

                await umaBinaryAdapter.initializeQuestion(questionID, ancillaryData, testRewardToken.address, 0, 0);

                // reinitialize the same questionID
                await expect(
                    umaBinaryAdapter.initializeQuestion(questionID, ancillaryData, testRewardToken.address, 0, 0),
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
                    umaBinaryAdapter
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
                    umaBinaryAdapter.initializeQuestion(questionID, ancillaryData, unsupportedToken.address, 0, 0),
                ).to.be.revertedWith("Adapter/unsupported-token");
            });

            it("should revert initialization if ancillary data is invalid", async function () {
                const questionID = createRandomQuestionID();

                // reverts if ancillary data length == 0 or > 8139
                await expect(
                    umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ethers.utils.randomBytes(0),
                        testRewardToken.address,
                        0,
                        0,
                    ),
                ).to.be.revertedWith("Adapter/invalid-ancillary-data");

                await expect(
                    umaBinaryAdapter.initializeQuestion(
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
                expect(await umaBinaryAdapter.readyToSettle(HashZero)).eq(false);

                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");

                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    reward,
                    proposalBond,
                );

                await optimisticOracle.mock.hasPrice.returns(true);
                expect(await umaBinaryAdapter.readyToSettle(questionID)).eq(true);
            });

            it("should correctly settle a question if it's readyToSettle", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const reward = ethers.utils.parseEther("10.0");
                const proposalBond = ethers.utils.parseEther("10000.0");

                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
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
                expect(await umaBinaryAdapter.connect(this.signers.tester).settle(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionSettled")
                    .withArgs(questionID, 1);

                // Verify settle block number != 0
                const questionData = await umaBinaryAdapter.questions(questionID);
                expect(questionData.settled).to.not.eq(0);

                // Ready to settle should be false, after settling
                const readyToSettle = await umaBinaryAdapter.readyToSettle(questionID);
                expect(readyToSettle).to.eq(false);
            });

            it("should revert if not readyToSettle", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();

                // Settle reverts if:
                // 1. QuestionID is not initialized
                const uninitQuestionID = HashZero;
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(uninitQuestionID)).to.be.revertedWith(
                    "Adapter/not-ready-to-settle",
                );

                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                await optimisticOracle.mock.hasPrice.returns(false);
                // 2. If OO doesn't have the price available
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter/not-ready-to-settle",
                );

                await optimisticOracle.mock.hasPrice.returns(true);

                // 3. If question is paused
                await (await umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(questionID)).wait();
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter/paused",
                );

                await (await umaBinaryAdapter.connect(this.signers.admin).unPauseQuestion(questionID)).wait();

                // 4. If question is already settled
                await (await umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).wait();
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter/not-ready-to-settle",
                );
            });

            // Pause tests
            it("should correctly pause resolution", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                expect(await umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionPaused")
                    .withArgs(questionID);

                const questionData = await umaBinaryAdapter.questions(questionID);

                // Verify paused
                expect(questionData.paused).to.eq(true);
            });

            it("should correctly unpause resolution", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                expect(await umaBinaryAdapter.connect(this.signers.admin).unPauseQuestion(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionUnpaused")
                    .withArgs(questionID);

                const questionData = await umaBinaryAdapter.questions(questionID);

                // Verify unpaused
                expect(questionData.paused).to.eq(false);
            });

            it("pause should revert when signer is not admin", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                await expect(
                    umaBinaryAdapter.connect(this.signers.tester).pauseQuestion(questionID),
                ).to.be.revertedWith("Adapter/not-authorized");
            });

            it("unpause should revert when signer is not admin", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                await expect(
                    umaBinaryAdapter.connect(this.signers.tester).unPauseQuestion(questionID),
                ).to.be.revertedWith("Adapter/not-authorized");
            });

            it("pause should revert if question is not initialized", async function () {
                await expect(umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(HashZero)).to.be.revertedWith(
                    "Adapter/not-initialized",
                );
            });

            it("should disallow atomic settling and resolution", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
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
                    args: [umaBinaryAdapter.address],
                    connect: this.signers.admin,
                });

                // TODO: case to be made that it's fine for settle and report to happen in the same block, revisit that assumption
                await expect(griefer.settleAndReport(questionID)).to.be.revertedWith(
                    "Adapter/same-block-settle-report",
                );
            });

            it("should correctly update the question", async function () {
                const title = ethers.utils.randomBytes(10).toString();
                const desc = ethers.utils.randomBytes(20).toString();
                const ancillaryData = createAncillaryData(title, desc);

                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
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
                    await umaBinaryAdapter
                        .connect(this.signers.admin)
                        .updateQuestion(questionID, ancillaryData, testRewardToken.address, newReward, newProposalBond),
                )
                    .to.emit(umaBinaryAdapter, "QuestionUpdated") // Emit QuestionUpdated from the Adapter
                    .and.to.emit(testRewardToken, "Transfer") // Transfer the new price request reward from caller to the Adapter
                    .withArgs(this.signers.admin.address, umaBinaryAdapter.address, newReward);

                const questionData = await umaBinaryAdapter.questions(questionID);

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

            it("update reverts if not admin", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
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
                    umaBinaryAdapter
                        .connect(this.signers.tester)
                        .updateQuestion(
                            questionID,
                            ethers.utils.randomBytes(10),
                            testRewardToken.address,
                            newReward,
                            newProposalBond,
                        ),
                ).to.be.revertedWith("Adapter/not-authorized");
            });
        });

        // describe("Condition Resolution scenarios", function () {
        //     let conditionalTokens: Contract;
        //     let optimisticOracle: MockContract;
        //     let testRewardToken: TestERC20;
        //     let umaBinaryAdapter: UmaCtfAdapter;
        //     let questionID: string;
        //     let bond: BigNumber;
        //     let snapshot: string;

        //     beforeEach(async function () {
        //         // capture hardhat chain snapshot
        //         snapshot = await takeSnapshot();

        //         const deployment = await setup();
        //         conditionalTokens = deployment.conditionalTokens;
        //         optimisticOracle = deployment.optimisticOracle;
        //         testRewardToken = deployment.testRewardToken;
        //         umaBinaryAdapter = deployment.umaBinaryAdapter;

        //         await optimisticOracle.mock.hasPrice.returns(true);

        //         questionID = createQuestionID(QUESTION_TITLE, DESC);
        //         bond = ethers.utils.parseEther("10000.0");

        //         // prepare condition with adapter as oracle
        //         await prepareCondition(conditionalTokens, umaBinaryAdapter.address, QUESTION_TITLE, DESC);

        //         // initialize question
        //         await initializeQuestion(
        //             umaBinaryAdapter,
        //             QUESTION_TITLE,
        //             DESC,
        //             testRewardToken.address,
        //             ethers.constants.Zero,
        //             bond,
        //         );

        //         // fast forward hardhat block time
        //         await hardhatIncreaseTime(7200);

        //         // Mock Optimistic Oracle setBond response
        //         await optimisticOracle.mock.setBond.returns(bond);

        //         // request resolution data
        //         await (await umaBinaryAdapter.requestResolutionData(questionID)).wait();

        //         // settle
        //         await optimisticOracle.mock.settleAndGetPrice.returns(1);
        //         const request = getMockRequest();
        //         await optimisticOracle.mock.getRequest.returns(request);
        //         await (await umaBinaryAdapter.settle(questionID)).wait();
        //     });

        //     afterEach(async function () {
        //         // revert to snapshot
        //         await revertToSnapshot(snapshot);
        //     });

        //     it("should correctly report [1,0] when YES", async function () {
        //         const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2);

        //         expect(await umaBinaryAdapter.reportPayouts(questionID))
        //             .to.emit(conditionalTokens, "ConditionResolution")
        //             .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [1, 0]);
        //     });

        //     it("should correctly report [0,1] when NO", async function () {
        //         const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2);
        //         const request = getMockRequest();
        //         request.resolvedPrice = ethers.constants.Zero;
        //         await optimisticOracle.mock.getRequest.returns(request);

        //         expect(await umaBinaryAdapter.reportPayouts(questionID))
        //             .to.emit(conditionalTokens, "ConditionResolution")
        //             .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [0, 1]);
        //     });

        //     it("should correctly report [1,1] when UNKNOWN", async function () {
        //         const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2);

        //         const request = getMockRequest();
        //         request.resolvedPrice = ethers.utils.parseEther("0.5");
        //         await optimisticOracle.mock.getRequest.returns(request);

        //         expect(await umaBinaryAdapter.reportPayouts(questionID))
        //             .to.emit(conditionalTokens, "ConditionResolution")
        //             .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [1, 1]);
        //     });

        //     it("reportPayouts emits ConditionResolved if resolution data exists", async function () {
        //         const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2);

        //         expect(await umaBinaryAdapter.reportPayouts(questionID))
        //             .to.emit(conditionalTokens, "ConditionResolution")
        //             .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [1, 0]);
        //     });

        //     it("reportPayouts emits QuestionResolved if resolution data exists", async function () {
        //         expect(await umaBinaryAdapter.reportPayouts(questionID))
        //             .to.emit(umaBinaryAdapter, "QuestionResolved")
        //             .withArgs(questionID, false);

        //         // Verify resolved flag on the QuestionData struct has been updated
        //         const questionData = await umaBinaryAdapter.questions(questionID);
        //         expect(await questionData.requestTimestamp).gt(0);
        //         expect(await questionData.resolved).eq(true);
        //     });

        //     it("reportPayouts reverts if OO returns malformed data", async function () {
        //         // Mock Optimistic Oracle returns invalid data
        //         const request = getMockRequest();
        //         request.resolvedPrice = BigNumber.from(21233);
        //         await optimisticOracle.mock.getRequest.returns(request);

        //         await expect(umaBinaryAdapter.reportPayouts(questionID)).to.be.revertedWith(
        //             "Adapter::reportPayouts: Invalid resolution data",
        //         );
        //     });

        //     it("reportPayouts reverts if question is paused", async function () {
        //         await umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(questionID);

        //         await expect(umaBinaryAdapter.reportPayouts(questionID)).to.be.revertedWith(
        //             "Adapter::getExpectedPayouts: Question is paused",
        //         );
        //     });

        //     it("should allow emergency reporting by the admin", async function () {
        //         // Verify admin resolution timestamp was set to zero upon question initialization
        //         const questionData = await umaBinaryAdapter.questions(questionID);

        //         expect(await questionData.adminResolutionTimestamp).to.eq(0);

        //         // Verify emergency resolution flag check returns false
        //         expect(await umaBinaryAdapter.isQuestionFlaggedForEmergencyResolution(questionID)).eq(false);

        //         // flag question for resolution
        //         expect(await umaBinaryAdapter.flagQuestionForEmergencyResolution(questionID))
        //             .to.emit(umaBinaryAdapter, "QuestionFlaggedForAdminResolution")
        //             .withArgs(questionID);

        //         // flag question for resolution should fail second time
        //         expect(umaBinaryAdapter.flagQuestionForEmergencyResolution(questionID)).to.be.revertedWith(
        //             "Adapter::emergencyReportPayouts: questionID is already flagged for emergency resolution",
        //         );

        //         // Verify admin resolution timestamp was set
        //         expect((await umaBinaryAdapter.questions(questionID)).adminResolutionTimestamp).gt(0);

        //         // Verify emergency resolution flag check returns true
        //         expect(await umaBinaryAdapter.isQuestionFlaggedForEmergencyResolution(questionID)).eq(true);

        //         // fast forward the chain to after the emergencySafetyPeriod
        //         await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

        //         // YES conditional payout
        //         const payouts = [1, 0];
        //         expect(await umaBinaryAdapter.emergencyReportPayouts(questionID, payouts))
        //             .to.emit(umaBinaryAdapter, "QuestionResolved")
        //             .withArgs(questionID, true);

        //         // Verify resolved flag on the QuestionData struct has been updated
        //         expect((await umaBinaryAdapter.questions(questionID)).resolved).eq(true);
        //     });

        //     it("should allow emergency reporting even if the question is paused", async function () {
        //         // Pause question
        //         await umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(questionID);

        //         // flag for emergency resolution
        //         await umaBinaryAdapter.flagQuestionForEmergencyResolution(questionID);

        //         // fast forward the chain to after the emergencySafetyPeriod
        //         await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

        //         // YES conditional payout
        //         const payouts = [1, 0];
        //         expect(await umaBinaryAdapter.emergencyReportPayouts(questionID, payouts))
        //             .to.emit(umaBinaryAdapter, "QuestionResolved")
        //             .withArgs(questionID, true);

        //         // Verify resolved flag on the QuestionData struct has been updated
        //         const questionData = await umaBinaryAdapter.questions(questionID);
        //         expect(await questionData.resolved).eq(true);
        //     });

        //     it("should revert if emergencyReport is called before the question is flagged for emergency resolution", async function () {
        //         // YES conditional payout
        //         const payouts = [1, 0];
        //         await expect(umaBinaryAdapter.emergencyReportPayouts(questionID, payouts)).to.be.revertedWith(
        //             "Adapter::emergencyReportPayouts: questionID is not flagged for emergency resolution",
        //         );
        //     });

        //     it("should revert if emergencyReport is called before the safety period", async function () {
        //         // flag for emergency resolution
        //         await umaBinaryAdapter.flagQuestionForEmergencyResolution(questionID);

        //         // YES conditional payout
        //         const payouts = [1, 0];
        //         await expect(umaBinaryAdapter.emergencyReportPayouts(questionID, payouts)).to.be.revertedWith(
        //             "Adapter::emergencyReportPayouts: safety period has not passed",
        //         );
        //     });

        //     it("should revert if emergencyReport is called with invalid payout", async function () {
        //         // flag for emergency resolution
        //         await umaBinaryAdapter.flagQuestionForEmergencyResolution(questionID);

        //         // fast forward the chain to post-emergencySafetyPeriod
        //         await hardhatIncreaseTime(emergencySafetyPeriod + 1000);

        //         // invalid conditional payout
        //         const nonBinaryPayoutVector = [0, 0, 0, 0, 1, 2, 3, 4, 5];
        //         await expect(
        //             umaBinaryAdapter.emergencyReportPayouts(questionID, nonBinaryPayoutVector),
        //         ).to.be.revertedWith("Adapter::emergencyReportPayouts: payouts must be binary");
        //     });

        //     it("should revert if emergencyReport is called from a non-admin", async function () {
        //         await expect(
        //             umaBinaryAdapter.connect(this.signers.tester).emergencyReportPayouts(questionID, [1, 0]),
        //         ).to.be.revertedWith("Adapter/not-authorized");
        //     });
        // });

        // describe("Early Resolution scenarios", function () {
        //     let conditionalTokens: Contract;
        //     let optimisticOracle: MockContract;
        //     let testRewardToken: TestERC20;
        //     let umaBinaryAdapter: UmaCtfAdapter;
        //     let resolutionTime: number;
        //     let questionID: string;
        //     let ancillaryData: Uint8Array;

        //     before(async function () {
        //         const deployment = await setup();
        //         conditionalTokens = deployment.conditionalTokens;
        //         optimisticOracle = deployment.optimisticOracle;
        //         testRewardToken = deployment.testRewardToken;
        //         umaBinaryAdapter = deployment.umaBinaryAdapter;
        //         const title = ethers.utils.randomBytes(5).toString();
        //         const desc = ethers.utils.randomBytes(10).toString();
        //         questionID = createQuestionID(title, desc);
        //         ancillaryData = createAncillaryData(title, desc);
        //         resolutionTime = Math.floor(new Date().getTime() / 1000) + 2000;

        //         await prepareCondition(conditionalTokens, umaBinaryAdapter.address, title, desc);
        //     });

        //     it("should correctly initialize an early resolution question", async function () {
        //         const bond = ethers.utils.parseEther("100");
        //         // Verify QuestionInitialized event emitted
        //         expect(
        //             await umaBinaryAdapter.initializeQuestion(
        //                 questionID,
        //                 ancillaryData,
        //                 resolutionTime,
        //                 testRewardToken.address,
        //                 0,
        //                 bond,
        //                 true,
        //             ),
        //         )
        //             .to.emit(umaBinaryAdapter, "QuestionInitialized")
        //             .withArgs(
        //                 questionID,
        //                 ethers.utils.hexlify(ancillaryData),
        //                 resolutionTime,
        //                 testRewardToken.address,
        //                 0,
        //                 bond,
        //                 true,
        //             );

        //         const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

        //         // Verify early resolution enabled flag on the questionData
        //         expect(returnedQuestionData.earlyResolutionEnabled).eq(true);
        //     });

        //     it("should request resolution data early", async function () {
        //         // Verify that ready to request resolution returns true since it's an early resolution
        //         expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).to.eq(true);

        //         // Request resolution data
        //         const receipt = await (
        //             await umaBinaryAdapter.connect(this.signers.admin).requestResolutionData(questionID)
        //         ).wait();

        //         // Ensure ResolutionDataRequested emitted
        //         const topic = umaBinaryAdapter.interface.getEventTopic("ResolutionDataRequested");
        //         const logs = receipt.logs.filter(log => log.topics[0] === topic);
        //         expect(logs.length).to.eq(1);

        //         const log = logs[0];
        //         const evt = await umaBinaryAdapter.interface.parseLog(log);

        //         const identifier = await umaBinaryAdapter.identifier();
        //         const data = await umaBinaryAdapter.questions(questionID);

        //         // Verify event args
        //         expect(evt.name).eq("ResolutionDataRequested");
        //         expect(evt.args.requestor).eq(this.signers.admin.address);
        //         expect(evt.args.requestTimestamp).eq(data.requestTimestamp);
        //         expect(evt.args.questionID).eq(questionID);
        //         expect(evt.args.identifier).eq(identifier);
        //         expect(evt.args.ancillaryData).eq(data.ancillaryData);
        //         expect(evt.args.reward).eq(ethers.constants.Zero);
        //         expect(evt.args.rewardToken).eq(testRewardToken.address);
        //         expect(evt.args.proposalBond).eq(ethers.utils.parseEther("100"));

        //         // Note: early resolution is correctly set to true as this is an early resolution
        //         expect(evt.args.earlyResolution).eq(true);

        //         // Verify that the requestTimestamp is set and is less than resolution time
        //         expect(data.requestTimestamp).to.be.gt(0);
        //         expect(data.requestTimestamp).to.be.lt(data.resolutionTime);
        //     });

        //     it("should revert if resolution data is requested twice", async function () {
        //         // Attempt to request data again for the same questionID
        //         await expect(umaBinaryAdapter.requestResolutionData(questionID)).to.be.revertedWith(
        //             "Adapter::requestResolutionData: Question not ready to be resolved",
        //         );
        //     });

        //     it("should allow new resolution data requests if OO sent ignore price", async function () {
        //         await optimisticOracle.mock.hasPrice.returns(true);

        //         // Optimistic Oracle sends the IGNORE_PRICE to the Adapter
        //         const request = await getMockRequest();
        //         request.resolvedPrice = ethers.constants.Zero;
        //         request.proposedPrice = BigNumber.from(IGNORE_PRICE);
        //         await optimisticOracle.mock.getRequest.returns(request);
        //         await optimisticOracle.mock.settleAndGetPrice.returns(IGNORE_PRICE);

        //         // Verfiy that ready to settle suceeds
        //         expect(await umaBinaryAdapter.readyToSettle(questionID)).to.eq(true);

        //         // Attempt to settle the early resolution question
        //         // Settle emits the QuestionReset event indicating that the question was not settled
        //         // Ensures that the proposal bond is returned to the price proposer
        //         expect(await umaBinaryAdapter.connect(this.signers.admin).settle(questionID))
        //             .to.emit(umaBinaryAdapter, "QuestionReset")
        //             .withArgs(questionID);

        //         // Allow new price requests by setting requestTimestamp to 0
        //         const questionData = await umaBinaryAdapter.questions(questionID);
        //         expect(questionData.requestTimestamp).to.eq(0);
        //         expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).to.eq(true);
        //     });

        //     it("should request new resolution data", async function () {
        //         expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).to.eq(true);

        //         const receipt = await (
        //             await umaBinaryAdapter.connect(this.signers.admin).requestResolutionData(questionID)
        //         ).wait();

        //         // Ensure ResolutionDataRequested emitted
        //         const topic = umaBinaryAdapter.interface.getEventTopic("ResolutionDataRequested");
        //         const logs = receipt.logs.filter(log => log.topics[0] === topic);
        //         expect(logs.length).to.eq(1);

        //         const log = logs[0];
        //         const evt = await umaBinaryAdapter.interface.parseLog(log);

        //         const identifier = await umaBinaryAdapter.identifier();
        //         const questionData = await umaBinaryAdapter.questions(questionID);

        //         // Verify event args
        //         expect(evt.name).eq("ResolutionDataRequested");
        //         expect(evt.args.requestor).eq(this.signers.admin.address);
        //         expect(evt.args.requestTimestamp).eq(questionData.requestTimestamp);
        //         expect(evt.args.questionID).eq(questionID);
        //         expect(evt.args.identifier).eq(identifier);
        //         expect(evt.args.ancillaryData).eq(questionData.ancillaryData);
        //         expect(evt.args.reward).eq(ethers.constants.Zero);
        //         expect(evt.args.rewardToken).eq(testRewardToken.address);
        //         expect(evt.args.proposalBond).eq(ethers.utils.parseEther("100"));

        //         // Note: early resolution is correctly set to true as this is an early resolution
        //         expect(evt.args.earlyResolution).eq(true);

        //         // Verify that the requestTimestamp is set and is less than resolution time
        //         expect(questionData.requestTimestamp).to.be.gt(0);
        //         expect(questionData.requestTimestamp).to.be.lt(questionData.resolutionTime);
        //     });

        //     it("should revert calling expected payouts if the question is not settled", async function () {
        //         await expect(umaBinaryAdapter.getExpectedPayouts(questionID)).to.be.revertedWith(
        //             "Adapter::getExpectedPayouts: questionID is not settled",
        //         );
        //     });

        //     it("should settle the question correctly", async function () {
        //         await optimisticOracle.mock.hasPrice.returns(true);
        //         await optimisticOracle.mock.getRequest.returns(getMockRequest());
        //         await optimisticOracle.mock.settleAndGetPrice.returns(1);

        //         // Settle the Question
        //         expect(await umaBinaryAdapter.connect(this.signers.tester).settle(questionID))
        //             .to.emit(umaBinaryAdapter, "QuestionSettled")
        //             .withArgs(questionID, 1, true);

        //         // Verify settled block number != 0
        //         const questionData = await umaBinaryAdapter.questions(questionID);
        //         expect(questionData.settled).to.not.eq(0);
        //     });

        //     it("should return expected payouts correctly after the question is settled", async function () {
        //         const expectedPayouts = await (
        //             await umaBinaryAdapter.getExpectedPayouts(questionID)
        //         ).map(el => el.toString());
        //         expect(expectedPayouts.length).to.eq(2);
        //         expect(expectedPayouts[0]).to.eq("1");
        //         expect(expectedPayouts[1]).to.eq("0");
        //     });

        //     it("should report payouts correctly", async function () {
        //         expect(await umaBinaryAdapter.reportPayouts(questionID))
        //             .to.emit(umaBinaryAdapter, "QuestionResolved")
        //             .withArgs(questionID, false);

        //         const questionData = await umaBinaryAdapter.questions(questionID);
        //         expect(await questionData.resolved).eq(true);
        //     });

        //     it("should return expected payouts correctly even after the question is resolved", async function () {
        //         const expectedPayouts = await (
        //             await umaBinaryAdapter.getExpectedPayouts(questionID)
        //         ).map(el => el.toString());
        //         expect(expectedPayouts.length).to.eq(2);
        //         expect(expectedPayouts[0]).to.eq("1");
        //         expect(expectedPayouts[1]).to.eq("0");
        //     });

        //     it("should fall back to standard resolution if past the resolution time", async function () {
        //         // Initialize a new question
        //         const title = ethers.utils.randomBytes(5).toString();
        //         const desc = ethers.utils.randomBytes(10).toString();
        //         const qID = await initializeQuestion(
        //             umaBinaryAdapter,
        //             title,
        //             desc,
        //             testRewardToken.address,
        //             ethers.constants.Zero,
        //             ethers.constants.Zero,
        //             undefined,
        //             true,
        //         );
        //         // Fast forward time
        //         await hardhatIncreaseTime(7200);

        //         // Verify that the question is not an early resolution
        //         const questionData = await umaBinaryAdapter.questions(qID);
        //         expect(questionData.requestTimestamp).to.eq(0);

        //         // request resolution data
        //         await (await umaBinaryAdapter.requestResolutionData(qID)).wait();

        //         // Settle using standard resolution
        //         // mocks for settlement and resolution
        //         await optimisticOracle.mock.hasPrice.returns(true);
        //         await optimisticOracle.mock.getRequest.returns(getMockRequest());
        //         await optimisticOracle.mock.settleAndGetPrice.returns(1);
        //         await prepareCondition(conditionalTokens, umaBinaryAdapter.address, title, desc);

        //         expect(await umaBinaryAdapter.connect(this.signers.tester).settle(qID))
        //             .to.emit(umaBinaryAdapter, "QuestionSettled")
        //             .withArgs(qID, 1, false); // Note: QuestionSettled event emitted with earlyResolution == false

        //         // Report payouts
        //         expect(await umaBinaryAdapter.reportPayouts(qID))
        //             .to.emit(umaBinaryAdapter, "QuestionResolved")
        //             .withArgs(qID, false);
        //     });

        //     it("should reset the question if the OO returns the Ignore price during standard settlement", async function () {
        //         // Initialize a new question
        //         const title = ethers.utils.randomBytes(5).toString();
        //         const desc = ethers.utils.randomBytes(10).toString();
        //         const qID = await initializeQuestion(
        //             umaBinaryAdapter,
        //             title,
        //             desc,
        //             testRewardToken.address,
        //             ethers.constants.Zero,
        //             ethers.constants.Zero,
        //             undefined,
        //             true,
        //         );
        //         // Fast forward time
        //         await hardhatIncreaseTime(7200);

        //         await (await umaBinaryAdapter.requestResolutionData(qID)).wait();

        //         // Verify requestTimestamp is > 0, i.e resolution data has been requested
        //         expect((await umaBinaryAdapter.questions(qID)).requestTimestamp).to.gt(0);

        //         // Settle using standard resolution, with the OO returning the IGNORE_PRICE
        //         const request = await getMockRequest();
        //         request.proposedPrice = BigNumber.from(IGNORE_PRICE);
        //         await optimisticOracle.mock.getRequest.returns(request);
        //         await optimisticOracle.mock.hasPrice.returns(true);
        //         await optimisticOracle.mock.settleAndGetPrice.returns(IGNORE_PRICE);

        //         expect(await umaBinaryAdapter.connect(this.signers.tester).settle(qID))
        //             .to.emit(umaBinaryAdapter, "QuestionReset")
        //             .withArgs(qID);

        //         // Verify requestTimestamp is 0, i.e Question has been reset
        //         const questionData = await umaBinaryAdapter.questions(qID);
        //         expect(questionData.requestTimestamp).to.eq(0);
        //     });
        // });
    });
});
