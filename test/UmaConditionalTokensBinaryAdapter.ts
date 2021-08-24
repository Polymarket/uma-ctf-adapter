import hre, { deployments, ethers } from "hardhat";
import { HashZero } from "@ethersproject/constants";

import { Contract } from "ethers";
import { expect } from "chai";
import { MockContract } from "@ethereum-waffle/mock-contract";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { MockConditionalTokens, TestERC20, UmaConditionalTokensBinaryAdapter } from "../typechain";
import { Signers } from "../types";
import { createQuestionID, deploy, deployMock, getAncillaryData, hardhatIncreaseTime } from "./helpers";
import { DESC, QUESTION_TITLE } from "./constants";

const setup = deployments.createFixture(async () => {
    const signers = await hre.ethers.getSigners();
    const admin: SignerWithAddress = signers[0];

    const conditionalTokens = await deploy<MockConditionalTokens>("MockConditionalTokens", {
        args: [],
        connect: admin,
    });
    const testRewardToken = await deploy<TestERC20>("TestERC20", {
        args: ["TestERC20", "TST"],
        connect: admin,
    });

    const optimisticOracle = await deployMock("IOptimisticOracle");
    await optimisticOracle.mock.requestPrice.returns(0);

    const umaBinaryAdapter: Contract = await deploy<UmaConditionalTokensBinaryAdapter>(
        "UmaConditionalTokensBinaryAdapter",
        {
            args: [conditionalTokens.address, optimisticOracle.address],
            connect: admin,
        },
    );

    return {
        conditionalTokens,
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
        describe("contracts are setup correctly", function () {
            let conditionalTokens: Contract;
            let optimisticOracle: MockContract;
            let umaBinaryAdapter: Contract;

            before(async function () {
                const deployment = await setup();
                conditionalTokens = deployment.conditionalTokens;
                optimisticOracle = deployment.optimisticOracle;
                umaBinaryAdapter = deployment.umaBinaryAdapter;
            });

            it("correctly sets up contracts", async function () {
                const returnedConditionalToken = await umaBinaryAdapter.conditionalTokenContract();
                expect(conditionalTokens.address).eq(returnedConditionalToken);

                const returnedOptimisticOracle = await umaBinaryAdapter.optimisticOracleContract();
                expect(optimisticOracle.address).eq(returnedOptimisticOracle);

                const returnedQueryIdentifier = await umaBinaryAdapter.oracleQueryIdentifier();
                expect(returnedQueryIdentifier).eq(
                    "0x5945535f4f525f4e4f5f51554552590000000000000000000000000000000000",
                );
            });
        });

        describe("Question scenarios", function () {
            let conditionalTokens: Contract;
            // let optimisticOracle: MockContract;
            let testRewardToken: Contract;
            let umaBinaryAdapter: Contract;

            before(async function () {
                const deployment = await setup();
                conditionalTokens = deployment.conditionalTokens;
                // optimisticOracle = deployment.optimisticOracle;
                testRewardToken = deployment.testRewardToken;
                umaBinaryAdapter = deployment.umaBinaryAdapter;
            });

            it("correctly prepares a question using the adapter as oracle", async function () {
                const oracle = umaBinaryAdapter.address;
                const questionID = createQuestionID(QUESTION_TITLE, DESC);
                const outcomeSlotCount = 2; // Only YES/NO
                const conditionID = await conditionalTokens.getConditionId(oracle, questionID, outcomeSlotCount);

                expect(await conditionalTokens.prepareCondition(oracle, questionID, outcomeSlotCount))
                    .to.emit(conditionalTokens, "ConditionPreparation")
                    .withArgs(conditionID, oracle, questionID, outcomeSlotCount);
            });

            it("correctly initializes a question", async function () {
                const questionID = createQuestionID(QUESTION_TITLE, DESC);
                const resolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;
                const ancillaryData = getAncillaryData(QUESTION_TITLE, DESC);
                const ancillaryDataHexlified = ethers.utils.hexlify(ancillaryData);
                expect(questionID).to.eq("0x5e2a133421146a87d09584a2a95ce678a4fba12efb4d27866affca702bf54fca");

                // Verify QuestionInitialized event emitted
                expect(
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        0,
                    ),
                )
                    .to.emit(umaBinaryAdapter, "QuestionInitialized")
                    .withArgs(questionID, ancillaryDataHexlified, resolutionTime, testRewardToken.address, 0);

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                // Verify question data stored
                expect(returnedQuestionData.questionID).eq(questionID);
                expect(returnedQuestionData.ancillaryData).eq(ancillaryDataHexlified);
                expect(returnedQuestionData.resolutionTime).eq(resolutionTime);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(0);
            });

            it("should revert when trying to reinitialize a question", async function () {
                const questionID = createQuestionID(QUESTION_TITLE, DESC);
                const resolutionTime = Math.floor(new Date().getTime() / 1000);
                const ancillaryData = ethers.utils.randomBytes(10);
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

            it("should correctly call readyToRequestResolution", async function () {
                const questionID = createQuestionID(QUESTION_TITLE, DESC);
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).eq(false);

                // 2 hours ahead
                await hardhatIncreaseTime(7200);
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).eq(true);
            });

            it("should correctly call request resolution data from the optimistic oracle", async function () {
                const questionID = createQuestionID(QUESTION_TITLE, DESC);
                expect(await umaBinaryAdapter.readyToRequestResolution(questionID)).eq(true);
                await (await umaBinaryAdapter.requestResolutionData(questionID)).wait();
                expect(await umaBinaryAdapter.resolutionDataRequests(questionID)).eq(true);
            });

            it("should revert if question is not initialized", async function () {
                const questionID = HashZero;
                await expect(umaBinaryAdapter.requestResolutionData(questionID)).to.be.revertedWith(
                    "Adapter::requestResolutionData: Question not ready to be resolved",
                );
            });

            it("should revert if resolution data previously requested", async function () {
                const questionID = createQuestionID(QUESTION_TITLE, DESC);
                await expect(umaBinaryAdapter.requestResolutionData(questionID)).to.be.revertedWith(
                    "Adapter::requestResolutionData: ResolutionData already requested",
                );
            });
        });
    });
});
