import hre, { deployments, ethers } from "hardhat";
import { HashZero } from "@ethersproject/constants";

import { Contract } from "@ethersproject/contracts";
import { expect } from "chai";
import { MockContract } from "@ethereum-waffle/mock-contract";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { BigNumber } from "ethers";
import { MockConditionalTokens, TestERC20, UmaConditionalTokensBinaryAdapter } from "../../typechain";
import { Signers } from "../../types";
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
} from "../helpers";
import { DESC, QUESTION_TITLE, thirtyDays } from "./constants";

const setup = deployments.createFixture(async () => {
    const signers = await hre.ethers.getSigners();
    const admin: SignerWithAddress = signers[0];

    const conditionalTokens: MockConditionalTokens = await deploy<MockConditionalTokens>("MockConditionalTokens", {
        args: [],
        connect: admin,
    });
    const testRewardToken: TestERC20 = await deploy<TestERC20>("TestERC20", {
        args: ["TestERC20", "TST"],
        connect: admin,
    });

    // Mint a million TST to admin
    await (await testRewardToken.mint(admin.address, BigNumber.from(ethers.utils.parseEther("1000000")))).wait();

    const optimisticOracle: MockContract = await deployMock("OptimisticOracleInterface");
    await optimisticOracle.mock.requestPrice.returns(0);

    const finderContract = await deployMock("FinderInterface");
    await finderContract.mock.getImplementationAddress.returns(optimisticOracle.address);

    const umaBinaryAdapter: UmaConditionalTokensBinaryAdapter = await deploy<UmaConditionalTokensBinaryAdapter>(
        "UmaConditionalTokensBinaryAdapter",
        {
            args: [conditionalTokens.address, finderContract.address],
            connect: admin,
        },
    );

    return {
        conditionalTokens,
        finderContract,
        optimisticOracle,
        testRewardToken,
        umaBinaryAdapter,
    };
});

describe("", function () {
    before(async function () {
        this.signers = {} as Signers;
        const signers = await hre.ethers.getSigners();
        this.signers.admin = signers[0];
        this.signers.deployer = signers[1];
        this.signers.tester = signers[2];
    });

    describe("Uma Conditional Token Binary Adapter", function () {
        describe("setup", function () {
            let conditionalTokens: Contract;
            let umaFinder: MockContract;
            let umaBinaryAdapter: UmaConditionalTokensBinaryAdapter;

            before(async function () {
                const deployment = await setup();
                conditionalTokens = deployment.conditionalTokens;
                umaFinder = deployment.finderContract;
                umaBinaryAdapter = deployment.umaBinaryAdapter;
            });

            it("correctly sets up contracts", async function () {
                // check that admin signer has proper role set up
                const adminRole = ethers.constants.HashZero;
                expect(await umaBinaryAdapter.hasRole(adminRole, this.signers.admin.address)).eq(true);
                expect(await umaBinaryAdapter.hasRole(adminRole, ethers.Wallet.createRandom().address)).eq(false);

                const returnedConditionalToken = await umaBinaryAdapter.conditionalTokenContract();
                expect(conditionalTokens.address).eq(returnedConditionalToken);

                const finderAddress = await umaBinaryAdapter.umaFinder();
                expect(umaFinder.address).eq(finderAddress);

                const returnedIdentifier = await umaBinaryAdapter.identifier();
                expect(returnedIdentifier).eq("0x5945535f4f525f4e4f5f51554552590000000000000000000000000000000000");
            });
        });

        describe("Question scenarios", function () {
            let conditionalTokens: Contract;
            let optimisticOracle: MockContract;
            let testRewardToken: TestERC20;
            let umaBinaryAdapter: UmaConditionalTokensBinaryAdapter;

            before(async function () {
                const deployment = await setup();
                conditionalTokens = deployment.conditionalTokens;
                optimisticOracle = deployment.optimisticOracle;
                testRewardToken = deployment.testRewardToken;
                umaBinaryAdapter = deployment.umaBinaryAdapter;
            });

            it("correctly prepares a question using the adapter as oracle", async function () {
                const oracle = umaBinaryAdapter.address;
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const outcomeSlotCount = 2; // Only YES/NO
                const conditionID = await conditionalTokens.getConditionId(oracle, questionID, outcomeSlotCount);

                expect(await conditionalTokens.prepareCondition(oracle, questionID, outcomeSlotCount))
                    .to.emit(conditionalTokens, "ConditionPreparation")
                    .withArgs(conditionID, oracle, questionID, outcomeSlotCount);
            });

            it("correctly initializes a question", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const resolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = 0;
                // Verify QuestionInitialized event emitted
                expect(
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized")
                    .withArgs(questionID, ancillaryDataHexlified, resolutionTime, testRewardToken.address, reward);

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.resolutionTime).eq(resolutionTime);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(reward);

                // Verify rewardToken allowance where adapter is owner and OO is spender
                const rewardTokenAllowance: BigNumber = await testRewardToken.allowance(
                    umaBinaryAdapter.address,
                    optimisticOracle.address,
                );
                expect(rewardTokenAllowance).eq(0);
            });

            it("correctly initializes a question with non-zero rewardToken", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const resolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = ethers.utils.parseEther("10.0");

                // Verify QuestionInitialized event emitted
                expect(
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized")
                    .withArgs(questionID, ancillaryDataHexlified, resolutionTime, testRewardToken.address, reward);

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.resolutionTime).eq(resolutionTime);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(reward);

                // Verify rewardToken allowance where adapter is owner and OO is spender
                const rewardTokenAllowance: BigNumber = await testRewardToken.allowance(
                    umaBinaryAdapter.address,
                    optimisticOracle.address,
                );
                expect(rewardTokenAllowance).eq(reward);
            });

            it("should revert when trying to reinitialize a question", async function () {
                // init question
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const resolutionTime = Math.floor(new Date().getTime() / 1000);
                const ancillaryData = ethers.utils.randomBytes(10);

                await umaBinaryAdapter.initializeQuestion(
                    questionID,
                    ancillaryData,
                    resolutionTime,
                    testRewardToken.address,
                    0,
                );

                // reinitialize the same questionID
                await expect(
                    umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        0,
                    ),
                ).to.be.revertedWith("Adapter::initializeQuestion: Question already initialized");
            });

            it("should correctly update an existing question", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const resolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = ethers.utils.parseEther("10.0");

                // Initialize Question
                await (
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                    )
                ).wait();

                // Update resolution time and reward
                const newResolutionTime = resolutionTime + 5000;
                const newReward = 0;
                expect(
                    await umaBinaryAdapter.updateQuestion(
                        questionID,
                        ancillaryDataHexlified,
                        newResolutionTime,
                        testRewardToken.address,
                        newReward,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionUpdated")
                    .withArgs(
                        questionID,
                        ancillaryDataHexlified,
                        newResolutionTime,
                        testRewardToken.address,
                        newReward,
                    );

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify question data is updated
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.resolutionTime).eq(newResolutionTime);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(newReward);

                // resolution flags always get reset after an update
                expect(returnedQuestionData.resolutionDataRequested).eq(false);
                expect(returnedQuestionData.resolved).eq(false);
            });

            it("should revert when a non-admin attempts to update the question", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const resolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = ethers.utils.parseEther("10.0");

                // Initialize Question
                await (
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                    )
                ).wait();

                await expect(
                    umaBinaryAdapter
                        .connect(this.signers.tester)
                        .updateQuestion(
                            questionID,
                            ancillaryDataHexlified,
                            resolutionTime,
                            testRewardToken.address,
                            reward,
                        ),
                ).to.be.revertedWith("Adapter::updateQuestion: caller does not have admin role");
            });

            it("should revert when trying to update a non-existent question", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const resolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = ethers.utils.parseEther("10.0");

                await expect(
                    umaBinaryAdapter.updateQuestion(
                        questionID,
                        ancillaryDataHexlified,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                    ),
                ).to.be.revertedWith("Adapter::updateQuestion: Question is not initialized");
            });

            it("should correctly call readyToRequestResolution", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                );

                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).eq(false);

                // 2 hours ahead
                await hardhatIncreaseTime(7200);
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).eq(true);
            });

            it("should correctly request resolution data from the OO", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                );
                const identifier = await umaBinaryAdapter.identifier();
                const questionData = await umaBinaryAdapter.questions(questionID);

                await optimisticOracle.mock.hasPrice.returns(true);
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).eq(true);

                expect(await umaBinaryAdapter.requestResolutionData(questionID))
                    .to.emit(umaBinaryAdapter, "ResolutionDataRequested")
                    .withArgs(
                        identifier,
                        questionData.resolutionTime,
                        questionID,
                        questionData.ancillaryData,
                        testRewardToken.address,
                        ethers.constants.Zero,
                    );

                const questionDataAfterRequest = await umaBinaryAdapter.questions(questionID);

                expect(await questionDataAfterRequest.resolutionDataRequested).eq(true);
                expect(await questionDataAfterRequest.resolved).eq(false);
            });

            it("requestResolutionData should revert if question is not initialized", async function () {
                const questionID = HashZero;
                await expect(umaBinaryAdapter.requestResolutionData(questionID)).to.be.revertedWith(
                    "Adapter::requestResolutionData: Question not ready to be resolved",
                );
            });

            it("requestResolutionData should revert if resolution data previously requested", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                );

                // Request resolution data once
                await umaBinaryAdapter.requestResolutionData(questionID);

                // Re-request resolution data
                await expect(umaBinaryAdapter.requestResolutionData(questionID)).to.be.revertedWith(
                    "Adapter::requestResolutionData: Question not ready to be resolved",
                );
            });

            it("should correctly call readyToReportPayouts if resolutionData is available from the OO", async function () {
                // Non existent questionID
                expect(await umaBinaryAdapter.readyToReportPayouts(HashZero)).eq(false);

                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                );

                // When resolutionData is available - resolutionOO::hasPrice returns true,
                await hardhatIncreaseTime(3600);
                await umaBinaryAdapter.requestResolutionData(questionID);
                await optimisticOracle.mock.hasPrice.returns(true);

                expect(await umaBinaryAdapter.readyToReportPayouts(questionID)).eq(true);
            });
        });

        describe("Condition Resolution scenarios", function () {
            let conditionalTokens: Contract;
            let optimisticOracle: MockContract;
            let testRewardToken: TestERC20;
            let umaBinaryAdapter: UmaConditionalTokensBinaryAdapter;
            let questionID: string;
            let snapshot: string;

            beforeEach(async function () {
                // capture hardhat chain snapshot
                snapshot = await takeSnapshot();

                const deployment = await setup();
                conditionalTokens = deployment.conditionalTokens;
                optimisticOracle = deployment.optimisticOracle;
                testRewardToken = deployment.testRewardToken;
                umaBinaryAdapter = deployment.umaBinaryAdapter;

                await optimisticOracle.mock.hasPrice.returns(true);

                questionID = createQuestionID(QUESTION_TITLE, DESC);

                // prepare condition with adapter as oracle
                await prepareCondition(conditionalTokens, umaBinaryAdapter.address, QUESTION_TITLE, DESC);

                // initialize question
                await initializeQuestion(
                    umaBinaryAdapter,
                    QUESTION_TITLE,
                    DESC,
                    testRewardToken.address,
                    ethers.constants.Zero,
                );

                // fast forward hardhat block time
                await hardhatIncreaseTime(7200);

                // request resolution data
                await umaBinaryAdapter.requestResolutionData(questionID);
            });

            afterEach(async function () {
                // revert to snapshot
                await revertToSnapshot(snapshot);
            });

            it("reportPayouts emits ConditionResolved if resolution data exists", async function () {
                const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2); // Mock Optimistic Oracle returns YES

                // Mock Optimistic Oracle returns YES
                await optimisticOracle.mock.settleAndGetPrice.returns(1);

                expect(await umaBinaryAdapter.reportPayouts(questionID))
                    .to.emit(conditionalTokens, "ConditionResolution")
                    .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [1, 0]);
            });

            it("reportPayouts emits QuestionResolved if resolution data exists", async function () {
                // Mock Optimistic Oracle returns YES
                await optimisticOracle.mock.settleAndGetPrice.returns(1);

                expect(await umaBinaryAdapter.reportPayouts(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionResolved")
                    .withArgs(questionID, false);

                // Verify resolved flag on the QuestionData struct has been updated
                const questionData = await umaBinaryAdapter.questions(questionID);
                expect(await questionData.resolutionDataRequested).eq(true);
                expect(await questionData.resolved).eq(true);
            });

            it("reportPayouts reverts if OO returns malformed data", async function () {
                // Mock Optimistic Oracle returns invalid data
                await optimisticOracle.mock.settleAndGetPrice.returns(2123);

                await expect(umaBinaryAdapter.reportPayouts(questionID)).to.be.revertedWith(
                    "Adapter::reportPayouts: Invalid resolution data",
                );
            });

            it("should allow emergency reporting by the owner", async function () {
                // fast forward the chain to after the emergencySafetyPeriod
                await hardhatIncreaseTime(thirtyDays + 1000);

                // YES conditional payout
                const payouts = [1, 0];
                expect(await umaBinaryAdapter.emergencyReportPayouts(questionID, payouts))
                    .to.emit(umaBinaryAdapter, "QuestionResolved")
                    .withArgs(questionID, true);

                // Verify resolved flag on the QuestionData struct has been updated
                const questionData = await umaBinaryAdapter.questions(questionID);
                expect(await questionData.resolved).eq(true);
            });

            it("should reverts if emergencyReport is called before the safety period", async function () {
                // YES conditional payout
                const payouts = [1, 0];
                await expect(umaBinaryAdapter.emergencyReportPayouts(questionID, payouts)).to.be.revertedWith(
                    "Adapter::emergencyReportPayouts: safety period has not passed",
                );
            });

            it("should reverts if emergencyReport is called with invalid payout", async function () {
                // fast forward the chain to after the emergencySafetyPeriod
                await hardhatIncreaseTime(thirtyDays + 1000);

                // invalid conditional payout
                const payouts = [10, 22];
                await expect(umaBinaryAdapter.emergencyReportPayouts(questionID, payouts)).to.be.revertedWith(
                    "Adapter::emergencyReportPayouts: payouts must be binary",
                );

                // invalid conditional payout
                const nonBinaryPayoutVector = [0, 0, 0, 0, 1, 2, 3, 4, 5];
                await expect(
                    umaBinaryAdapter.emergencyReportPayouts(questionID, nonBinaryPayoutVector),
                ).to.be.revertedWith("Adapter::emergencyReportPayouts: payouts must be binary");
            });
        });
    });
});
