import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;

    const { deployer } = await getNamedAccounts();

    const conditionalTokens = await deployments.get("ConditionalTokens");
    const finder = await deployments.get("Finder");

    await deployments.deploy("UmaCtfAdapter", {
        from: deployer,
        args: [conditionalTokens.address, finder.address],
    });
};

export default func;
