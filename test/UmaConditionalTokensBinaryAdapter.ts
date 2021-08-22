import hre, { deployments } from "hardhat";

import { Contract } from "ethers";
import { expect } from "chai";
import { MockContract } from "@ethereum-waffle/mock-contract";
import { UmaConditionalTokensBinaryAdapter } from "../typechain";
import { Signers } from "../types";
import { deploy, deployMock } from "./helpers";

const setup = deployments.createFixture(async () => {
    const conditionalToken = await deployMock("IConditionalTokens");

    const optimisticOracle = await deployMock("IOptimisticOracle");

    const umaBinaryAdapter: Contract = await deploy<UmaConditionalTokensBinaryAdapter>(
        "UmaConditionalTokensBinaryAdapter",
        {
            args: [conditionalToken.address, optimisticOracle.address],
        },
    );

    return {
        conditionalToken,
        optimisticOracle,
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
                expect(conditionalToken).eq(returnedConditionalToken);

                const returnedOptimisticOracle = await umaBinaryAdapter.optimisticOracleContract();
                expect(optimisticOracle).eq(returnedOptimisticOracle);
            });
        });
    });
});
