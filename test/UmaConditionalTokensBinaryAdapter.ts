import hre from "hardhat";
import { Artifact } from "hardhat/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { deployMockContract } from "@ethereum-waffle/mock-contract";
import { expect } from "chai";
import { deployments, ethers } from "hardhat";

import { UmaConditionalTokensBinaryAdapter, IConditionalTokens, IOptimisticOracle } from "../typechain";
import { Signers } from "../types";
import { deploy } from "./helpers";
import { Contract } from "ethers";



const setup = deployments.createFixture(async () => {
    const conditionalToken: Contract = await deploy<IConditionalTokens>("IConditionalTokens", {
        args: [],
    });

    const optimisticOracle: Contract = await deploy<IOptimisticOracle>("IOptimisticOracle", {
        args: [],
    });

    const umaBinaryAdapter: Contract = await deploy<UmaConditionalTokensBinaryAdapter>("UmaConditionalTokensBinaryAdapter", {
        args: [conditionalToken.address, optimisticOracle.address],
    });

    return {
        conditionalToken,
        optimisticOracle,
        umaBinaryAdapter
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
        let conditionalToken: Contract;
        let optimisticOracle: Contract;
        let umaBinaryAdapter: Contract;

        before(async function (){
            const deployment = await setup();
            conditionalToken = deployment.conditionalToken;
            optimisticOracle = deployment.optimisticOracle;
            umaBinaryAdapter = deployment.umaBinaryAdapter;
        });

    });

})