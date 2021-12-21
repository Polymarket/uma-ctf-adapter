import hre, { deployments, ethers } from "hardhat";
import { HashZero } from "@ethersproject/constants";
import { Contract } from "@ethersproject/contracts";
import { expect } from "chai";
import { MockContract } from "@ethereum-waffle/mock-contract";
import { BigNumber } from "ethers";
import { Griefer, MockConditionalTokens, TestERC20, UmaConditionalTokensBinaryAdapter } from "../../typechain";
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
} from "../helpers";
import { DESC, IGNORE_PRICE, QUESTION_TITLE, thirtyDays } from "./constants";

const setup = deployments.createFixture(async () => {
    const signers = await hre.ethers.getSigners();
    const admin = signers[0];

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
        this.signers = {};
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
                ).to.be.revertedWith("Auth/not-authorized");
            });

            it("correctly sets up contracts", async function () {
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

            // Question initialization tests
            it("correctly initializes a question", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const resolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = 0;
                const proposalBond = 0;

                // Verify QuestionInitialized event emitted
                expect(
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                        proposalBond,
                        false,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized")
                    .withArgs(
                        questionID,
                        ancillaryDataHexlified,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                        proposalBond,
                        false,
                    );

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.resolutionTime).eq(resolutionTime);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(reward);
                // ensure paused defaults to false
                expect(returnedQuestionData.paused).eq(false);
                expect(returnedQuestionData.settled).eq(0);

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
                        0,
                        false,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized")
                    .withArgs(
                        questionID,
                        ancillaryDataHexlified,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                        0,
                        false,
                    );

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.resolutionTime).eq(resolutionTime);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(reward);
                expect(returnedQuestionData.proposalBond).eq(0);

                // Verify rewardToken allowance where adapter is owner and OO is spender
                const rewardTokenAllowance: BigNumber = await testRewardToken.allowance(
                    umaBinaryAdapter.address,
                    optimisticOracle.address,
                );
                expect(rewardTokenAllowance).eq(reward);
            });

            it("correctly initializes a question with non-zero proposalBond and rewardToken", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = createQuestionID(title, desc);
                const resolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;
                const ancillaryData = createAncillaryData(title, desc);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                const reward = ethers.utils.parseEther("10.0");

                // 10000 TST bond
                const proposalBond = ethers.utils.parseEther("10000.0");

                // Verify QuestionInitialized event emitted
                expect(
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                        proposalBond,
                        false,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized")
                    .withArgs(
                        questionID,
                        ancillaryDataHexlified,
                        resolutionTime,
                        testRewardToken.address,
                        reward,
                        proposalBond,
                        false,
                    );

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.resolutionTime).eq(resolutionTime);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(reward);
                expect(returnedQuestionData.proposalBond).eq(proposalBond);

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
                    0,
                    false,
                );

                // reinitialize the same questionID
                await expect(
                    umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        0,
                        0,
                        false,
                    ),
                ).to.be.revertedWith("Adapter::initializeQuestion: Question already initialized");
            });

            // RequestResolution tests
            it("should correctly call readyToRequestResolution", async function () {
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

                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).eq(false);

                // 2 hours ahead
                await hardhatIncreaseTime(7200);
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).eq(true);
            });

            it("should correctly request resolution data from the OO", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const bond = ethers.utils.parseEther("10000.0");

                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    bond,
                );
                const identifier = await umaBinaryAdapter.identifier();
                const questionData = await umaBinaryAdapter.questions(questionID);

                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.setBond.returns(bond);

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
                        bond,
                        false,
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
                    ethers.constants.Zero,
                );

                // Request resolution data once
                await (await umaBinaryAdapter.requestResolutionData(questionID)).wait();

                // Re-request resolution data
                // Ensures that setBond on the OO is only called *once*
                await expect(umaBinaryAdapter.requestResolutionData(questionID)).to.be.revertedWith(
                    "Adapter::requestResolutionData: Question not ready to be resolved",
                );
            });

            // Settle tests
            it("should correctly call readyToSettle if resolutionData is available from the OO", async function () {
                // Non existent questionID
                expect(await umaBinaryAdapter.readyToSettle(HashZero)).eq(false);

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

                // When resolutionData is available - resolutionOO::hasPrice returns true,
                await hardhatIncreaseTime(3600);
                await umaBinaryAdapter.requestResolutionData(questionID);
                await optimisticOracle.mock.hasPrice.returns(true);

                expect(await umaBinaryAdapter.readyToSettle(questionID)).eq(true);
            });

            it("should correctly settle a question if it's readyToSettle", async function () {
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

                // Boilerplate/mocks to ensure readyToSettle
                await hardhatIncreaseTime(3600);
                await umaBinaryAdapter.requestResolutionData(questionID);
                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.settleAndGetPrice.returns(1);

                // Verify QuestionSettled emitted
                expect(await umaBinaryAdapter.connect(this.signers.tester).settle(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionSettled")
                    .withArgs(questionID, false);

                // Verify settle block number != 0
                const questionData = await umaBinaryAdapter.questions(questionID);
                expect(questionData.settled).to.not.eq(0);
            });

            it("should revert if not readyToSettle", async function () {
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();

                // Settle reverts if:
                // 1. QuestionID is not initialized
                const uninitQuestionID = HashZero;
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(uninitQuestionID)).to.be.revertedWith(
                    "Adapter::settle: questionID is not ready to be settled",
                );

                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                );

                // 2. if resolutionData is not requested
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter::settle: questionID is not ready to be settled",
                );

                await hardhatIncreaseTime(3600);
                await umaBinaryAdapter.requestResolutionData(questionID);

                await optimisticOracle.mock.settleAndGetPrice.returns(1);
                await optimisticOracle.mock.hasPrice.returns(false);

                // 3. If OO doesn't have the price available
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter::settle: questionID is not ready to be settled",
                );

                await optimisticOracle.mock.hasPrice.returns(true);

                // 4. If question is paused
                await (await umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(questionID)).wait();
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter::settle: Question is paused",
                );
                await (await umaBinaryAdapter.connect(this.signers.admin).unPauseQuestion(questionID)).wait();

                // 5. If question is already settled
                await (await umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).wait();
                await expect(umaBinaryAdapter.connect(this.signers.admin).settle(questionID)).to.be.revertedWith(
                    "Adapter::settle: questionID is not ready to be settled",
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
                    // set resolutionTime in the past so readyToRequestResolution returns true
                    Math.floor(Date.now() / 1000) - 60 * 60 * 24,
                );

                expect(await umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionPaused")
                    .withArgs(questionID);

                const questionData = await umaBinaryAdapter.questions(questionID);

                // Verify paused
                expect(questionData.paused).to.eq(true);

                // Verify requestResolutionData reverts if paused
                await expect(
                    umaBinaryAdapter.connect(this.signers.admin).requestResolutionData(questionID),
                ).to.be.revertedWith("Adapter::requestResolutionData: Question is paused");
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
                    Math.floor(Date.now() / 1000) - 60 * 60 * 24,
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
                ).to.be.revertedWith("Auth/not-authorized");
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
                ).to.be.revertedWith("Auth/not-authorized");
            });

            it("pause should revert if question is not initialized", async function () {
                await expect(umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(HashZero)).to.be.revertedWith(
                    "Adapter::pauseQuestion: questionID is not initialized",
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
                    Math.floor(Date.now() / 1000) - 60 * 60 * 24,
                );
                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.settleAndGetPrice.returns(1);

                const request = getMockRequest();
                await optimisticOracle.mock.getRequest.returns(request);
                await umaBinaryAdapter.requestResolutionData(questionID);

                const griefer: Griefer = await deploy<Griefer>("Griefer", {
                    args: [umaBinaryAdapter.address],
                    connect: this.signers.admin,
                });

                await expect(griefer.settleAndReport(questionID)).to.be.revertedWith(
                    "Adapter::reportPayouts: Attempting to settle and reportPayouts in the same block",
                );
            });

            // Finder address tests
            it("should update the finder address", async function () {
                const finderAddress = await umaBinaryAdapter.umaFinder();
                const newFinderAddress = ethers.Wallet.createRandom();
                expect(await umaBinaryAdapter.setFinderAddress(newFinderAddress.address))
                    .to.emit(umaBinaryAdapter, "NewFinderAddress")
                    .withArgs(finderAddress, newFinderAddress.address);
            });

            it("should revert if finder address updater is not the admin", async function () {
                await expect(
                    umaBinaryAdapter
                        .connect(this.signers.tester)
                        .setFinderAddress(ethers.Wallet.createRandom().address),
                ).to.be.revertedWith("Auth/not-authorized");
            });
        });

        describe("Condition Resolution scenarios", function () {
            let conditionalTokens: Contract;
            let optimisticOracle: MockContract;
            let testRewardToken: TestERC20;
            let umaBinaryAdapter: UmaConditionalTokensBinaryAdapter;
            let questionID: string;
            let bond: BigNumber;
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
                bond = ethers.utils.parseEther("10000.0");

                // prepare condition with adapter as oracle
                await prepareCondition(conditionalTokens, umaBinaryAdapter.address, QUESTION_TITLE, DESC);

                // initialize question
                await initializeQuestion(
                    umaBinaryAdapter,
                    QUESTION_TITLE,
                    DESC,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    bond,
                );

                // fast forward hardhat block time
                await hardhatIncreaseTime(7200);

                // Mock Optimistic Oracle setBond response
                await optimisticOracle.mock.setBond.returns(bond);

                // request resolution data
                await (await umaBinaryAdapter.requestResolutionData(questionID)).wait();

                // settle
                await optimisticOracle.mock.settleAndGetPrice.returns(1);
                const request = getMockRequest();
                await optimisticOracle.mock.getRequest.returns(request);
                await (await umaBinaryAdapter.settle(questionID)).wait();
            });

            afterEach(async function () {
                // revert to snapshot
                await revertToSnapshot(snapshot);
            });

            it("should correctly report [1,0] when YES", async function () {
                const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2);

                expect(await umaBinaryAdapter.reportPayouts(questionID))
                    .to.emit(conditionalTokens, "ConditionResolution")
                    .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [1, 0]);
            });

            it("should correctly report [0,1] when NO", async function () {
                const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2);
                const request = getMockRequest();
                request.resolvedPrice = ethers.constants.Zero;
                await optimisticOracle.mock.getRequest.returns(request);

                expect(await umaBinaryAdapter.reportPayouts(questionID))
                    .to.emit(conditionalTokens, "ConditionResolution")
                    .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [0, 1]);
            });

            it("should correctly report [1,1] when UNKNOWN", async function () {
                const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2);

                const request = getMockRequest();
                request.resolvedPrice = ethers.utils.parseEther("0.5");
                await optimisticOracle.mock.getRequest.returns(request);

                expect(await umaBinaryAdapter.reportPayouts(questionID))
                    .to.emit(conditionalTokens, "ConditionResolution")
                    .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [1, 1]);
            });

            it("reportPayouts emits ConditionResolved if resolution data exists", async function () {
                const conditionID = await conditionalTokens.getConditionId(umaBinaryAdapter.address, questionID, 2);

                expect(await umaBinaryAdapter.reportPayouts(questionID))
                    .to.emit(conditionalTokens, "ConditionResolution")
                    .withArgs(conditionID, umaBinaryAdapter.address, questionID, 2, [1, 0]);
            });

            it("reportPayouts emits QuestionResolved if resolution data exists", async function () {
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
                const request = getMockRequest();
                request.resolvedPrice = BigNumber.from(21233);
                await optimisticOracle.mock.getRequest.returns(request);

                await expect(umaBinaryAdapter.reportPayouts(questionID)).to.be.revertedWith(
                    "Adapter::reportPayouts: Invalid resolution data",
                );
            });

            it("reportPayouts reverts if question is paused", async function () {
                await umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(questionID);

                await expect(umaBinaryAdapter.reportPayouts(questionID)).to.be.revertedWith(
                    "Adapter::getExpectedPayouts: Question is paused",
                );
            });

            it("should allow emergency reporting by the admin", async function () {
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

            it("should allow emergency reporting even if the question is paused", async function () {
                // Pause question
                await umaBinaryAdapter.connect(this.signers.admin).pauseQuestion(questionID);

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

            it("should revert if emergencyReport is called before the safety period", async function () {
                // YES conditional payout
                const payouts = [1, 0];
                await expect(umaBinaryAdapter.emergencyReportPayouts(questionID, payouts)).to.be.revertedWith(
                    "Adapter::emergencyReportPayouts: safety period has not passed",
                );
            });

            it("should revert if emergencyReport is called with invalid payout", async function () {
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

            it("should revert if emergencyReport is called from a non-admin", async function () {
                await expect(
                    umaBinaryAdapter.connect(this.signers.tester).emergencyReportPayouts(questionID, [1, 0]),
                ).to.be.revertedWith("Auth/not-authorized");
            });
        });

        describe("Early expiry scenarios", function () {
            let conditionalTokens: Contract;
            let optimisticOracle: MockContract;
            let testRewardToken: TestERC20;
            let umaBinaryAdapter: UmaConditionalTokensBinaryAdapter;
            let resolutionTime: number;
            let questionID: string;
            let ancillaryData: Uint8Array;

            before(async function () {
                const deployment = await setup();
                conditionalTokens = deployment.conditionalTokens;
                optimisticOracle = deployment.optimisticOracle;
                testRewardToken = deployment.testRewardToken;
                umaBinaryAdapter = deployment.umaBinaryAdapter;
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                questionID = createQuestionID(title, desc);
                ancillaryData = createAncillaryData(title, desc);
                resolutionTime = Math.floor(new Date().getTime() / 1000) + 2000;

                await prepareCondition(conditionalTokens, umaBinaryAdapter.address, title, desc);
            });

            it("should correctly initialize an early expiry question", async function () {
                // Verify QuestionInitialized event emitted
                expect(
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        0,
                        0,
                        true,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized")
                    .withArgs(
                        questionID,
                        ethers.utils.hexlify(ancillaryData),
                        resolutionTime,
                        testRewardToken.address,
                        0,
                        0,
                        true,
                    );

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify early expiry enabled flag on the questionData
                expect(returnedQuestionData.earlyExpiryEnabled).eq(true);
            });

            it("should request resolution data early", async function () {
                // Verify that ready to request resolution returns true since it's an early expiry
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).to.eq(true);

                // Request resolution data
                expect(await umaBinaryAdapter.requestResolutionData(questionID)).to.emit(
                    umaBinaryAdapter,
                    "ResolutionDataRequested",
                );

                const questionData = await umaBinaryAdapter.questions(questionID);
                const earlyExpiryTimestamp = questionData.earlyExpiryTimestamp;

                // Verify that the earlyExpiryTimestamp is set and is less than resolution time
                expect(earlyExpiryTimestamp).to.be.gt(0);
                expect(earlyExpiryTimestamp).to.be.lt(questionData.resolutionTime);
            });

            it("should revert if res data is requested twice", async function () {
                // Attempt to request data again for the same questionID
                await expect(umaBinaryAdapter.requestResolutionData(questionID)).to.be.revertedWith(
                    "Adapter::requestResolutionData: Question not ready to be resolved",
                );
            });

            it("should allow new res data requests if OO sent ignore price", async function () {
                await optimisticOracle.mock.hasPrice.returns(true);

                // Optimistic Oracle sends the IGNORE_PRICE to the Adapter
                const request = await getMockRequest();
                request.resolvedPrice = ethers.constants.Zero;
                request.proposedPrice = IGNORE_PRICE;
                await optimisticOracle.mock.getRequest.returns(request);

                // Verfiy that ready to settle suceeds
                expect(await umaBinaryAdapter.readyToSettle(questionID)).to.eq(true);

                // Attempt to settle the early expiry question
                await umaBinaryAdapter.settle(questionID);

                // Since the OO sent the IGNORE_PRICE, the Adapter will NOT settle the question
                // But instead will allow new price requests by setting resolutionDataRequested to false
                const questionData = await umaBinaryAdapter.questions(questionID);
                expect(questionData.resolutionDataRequested).to.eq(false);
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).to.eq(true);
            });

            it("should request new resolution data", async function () {
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).to.eq(true);

                // Request resolution data
                expect(await umaBinaryAdapter.requestResolutionData(questionID)).to.emit(
                    umaBinaryAdapter,
                    "ResolutionDataRequested",
                );
                const questionData = await umaBinaryAdapter.questions(questionID);

                // Verify that the earlyExpiryTimestamp is set and is less than resolution time
                expect(questionData.earlyExpiryTimestamp).to.be.gt(0);
                expect(questionData.earlyExpiryTimestamp).to.be.lt(questionData.resolutionTime);
            });

            it("should settle the question correctly", async function () {
                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                await optimisticOracle.mock.settleAndGetPrice.returns(1);

                // Settle the Question
                expect(await umaBinaryAdapter.connect(this.signers.tester).settle(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionSettled")
                    .withArgs(questionID, true);

                // Verify settled block number != 0
                const questionData = await umaBinaryAdapter.questions(questionID);
                expect(questionData.settled).to.not.eq(0);
            });

            it("should return expected payouts", async function () {
                const expectedPayouts = await (
                    await umaBinaryAdapter.getExpectedPayouts(questionID)
                ).map(el => el.toString());
                expect(expectedPayouts.length).to.eq(2);
                expect(expectedPayouts[0]).to.eq("1");
                expect(expectedPayouts[1]).to.eq("0");
            });

            it("should report payouts correctly", async function () {
                expect(await umaBinaryAdapter.reportPayouts(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionResolved")
                    .withArgs(questionID, false);

                const questionData = await umaBinaryAdapter.questions(questionID);
                expect(await questionData.resolutionDataRequested).eq(true);
                expect(await questionData.resolved).eq(true);
            });

            it("should fallback to standard resolution if past the resolution time", async function () {
                // Initialize a new question 
                const title = ethers.utils.randomBytes(5).toString();
                const desc = ethers.utils.randomBytes(10).toString();
                const questionID = await initializeQuestion(
                    umaBinaryAdapter,
                    title,
                    desc,
                    testRewardToken.address,
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                    undefined,
                    true
                );
                // Fast forward time
                await hardhatIncreaseTime(7200);

                // Verify that isEarlyExpiry is false
                expect(await umaBinaryAdapter.isEarlyExpiry(questionID)).to.eq(false)

                // request resolution data
                await (await umaBinaryAdapter.requestResolutionData(questionID)).wait();

                // Verify that early expiry timestamp is not set
                const questionData = await umaBinaryAdapter.questions(questionID);
                expect(questionData.earlyExpiryEnabled).to.eq(true);
                expect(questionData.earlyExpiryTimestamp).to.eq(0);

                // Settle using standard resolution
                // mocks for settlement and resolution
                await optimisticOracle.mock.hasPrice.returns(true);
                await optimisticOracle.mock.getRequest.returns(getMockRequest());
                await optimisticOracle.mock.settleAndGetPrice.returns(1);
                await prepareCondition(conditionalTokens, umaBinaryAdapter.address, title, desc);

                expect(await umaBinaryAdapter.connect(this.signers.tester).settle(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionSettled")
                    .withArgs(questionID, false); //Note QuestionSettled emitted with earlyExpiry == false

                //Report payouts
                expect(await umaBinaryAdapter.reportPayouts(questionID))
                    .to.emit(umaBinaryAdapter, "QuestionResolved")
                    .withArgs(questionID, false);
            });
        });
    });
});