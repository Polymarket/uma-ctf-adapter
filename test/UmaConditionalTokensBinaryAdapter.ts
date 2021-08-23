import hre, { deployments, ethers } from "hardhat";

import { Contract } from "ethers";
import { expect } from "chai";
import { MockContract } from "@ethereum-waffle/mock-contract";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { TestERC20, UmaConditionalTokensBinaryAdapter } from "../typechain";
import { Signers } from "../types";
import { createQuestionID, deploy, deployMock } from "./helpers";

const setup = deployments.createFixture(async () => {
    const signers = await hre.ethers.getSigners();
    const admin: SignerWithAddress = signers[0];
    const conditionalToken = await deployMock("IConditionalTokens");
    const testRewardToken = await deploy<TestERC20>("TestERC20", {
        args: ["TestERC20", "TST"],
        connect: admin,
    });

    const optimisticOracle = await deployMock("IOptimisticOracle");

    const umaBinaryAdapter: Contract = await deploy<UmaConditionalTokensBinaryAdapter>(
        "UmaConditionalTokensBinaryAdapter",
        {
            args: [conditionalToken.address, optimisticOracle.address],
            connect: admin,
        },
    );

    return {
        conditionalToken,
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
            let conditionalToken: MockContract;
            let optimisticOracle: MockContract;
            let umaBinaryAdapter: Contract;

            before(async function () {
                const deployment = await setup();
                conditionalToken = deployment.conditionalToken;
                optimisticOracle = deployment.optimisticOracle;
                umaBinaryAdapter = deployment.umaBinaryAdapter;
            });

            it("correctly sets up contracts", async function () {
                const returnedConditionalToken = await umaBinaryAdapter.conditionalTokenContract();
                expect(conditionalToken.address).eq(returnedConditionalToken);

                const returnedOptimisticOracle = await umaBinaryAdapter.optimisticOracleContract();
                expect(optimisticOracle.address).eq(returnedOptimisticOracle);

                const returnedQueryIdentifier = await umaBinaryAdapter.oracleQueryIdentifier();
                expect(returnedQueryIdentifier).eq(
                    "0x5945535f4f525f4e4f5f51554552590000000000000000000000000000000000",
                );
            });
        });

        describe("Question scenarios", function () {
            // let conditionalToken: MockContract;
            // let optimisticOracle: MockContract;
            let testRewardToken: Contract;
            let umaBinaryAdapter: Contract;

            before(async function () {
                const deployment = await setup();
                umaBinaryAdapter = deployment.umaBinaryAdapter;
                testRewardToken = deployment.testRewardToken;
            });

            it("correctly initializes a question", async function () {
                const questionTitle = "This is a mock question title?";
                const description =
                    "This is a binary market on the mock question title. p1: 0, p2: 1. Where p2 corresponds to YES, p1 to a NO";
                const questionID = createQuestionID(questionTitle, description);
                const resolutionTime = Math.floor(new Date().getTime() / 1000);
                const ancillaryData = ethers.utils.toUtf8Bytes(questionTitle + description);

                await (
                    await umaBinaryAdapter.initializeQuestion(
                        questionID,
                        ancillaryData,
                        resolutionTime,
                        testRewardToken.address,
                        0,
                    )
                ).wait();

                const returnedQuestionData = await umaBinaryAdapter.questions(questionID);

                expect(returnedQuestionData.questionID).eq(questionID);
                // const ancillaryDataResp = ethers.utils.toUtf8String(ancillaryData);
                // expect(ancillaryDataResp).eq(ancillaryData);
                expect(returnedQuestionData.resolutionTime).eq(resolutionTime);
                expect(returnedQuestionData.rewardToken).eq(testRewardToken.address);
                expect(returnedQuestionData.reward).eq(0);
            });
        });
    });
});
