import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;

    const { deployer } = await getNamedAccounts();

    const conditionalTokens = await deployments.get("ConditionalTokens");
    const optimisticOracle = await deployments.get("OptimisticOracle");

    await deployments.deploy("UmaConditionalTokensBinaryAdapter", {
        from: deployer,
        args: [conditionalTokens.address, optimisticOracle.address],
    });
};

export default func;
