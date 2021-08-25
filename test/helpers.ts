import { MockContract } from "ethereum-waffle";
import { Contract, Signer } from "ethers";
import { deployments, ethers, waffle } from "hardhat";

export function createQuestionID(title: string, description: string): string {
    return ethers.utils.solidityKeccak256(["string", "string"], [title, description]);
}

export function createAncillaryData(title: string, description: string): Uint8Array {
    return ethers.utils.toUtf8Bytes(`q: ${title}d: ${description}`);
}

export async function prepareCondition(
    conditionalTokens: Contract,
    oracle: string,
    title: string,
    description: string,
): Promise<void> {
    const questionID = createQuestionID(title, description);
    await conditionalTokens.prepareCondition(oracle, questionID, 2);
}

export async function initializeQuestion(
    adapter: Contract,
    title: string,
    description: string,
    rewardAddress: string,
    resolutionTime?: number,
): Promise<string> {
    const questionID = createQuestionID(title, description);
    const defaultResolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;

    const resTime = resolutionTime != null ? resolutionTime : defaultResolutionTime;
    const ancillaryData = createAncillaryData(title, description);

    await adapter.initializeQuestion(questionID, ancillaryData, resTime, rewardAddress, 0);
    return questionID;
}

export async function deploy<T extends Contract>(
    deploymentName: string,
    { from, args, connect }: { from?: string; args: Array<unknown>; connect?: Signer },
    contractName: string = deploymentName,
): Promise<T> {
    // Unless overridden, deploy from named address "deployer"
    if (from === undefined) {
        const deployer = await ethers.getNamedSigner("deployer");
        // eslint-disable-next-line no-param-reassign
        from = deployer.address;
    }

    const deployment = await deployments.deploy(deploymentName, {
        from,
        contract: contractName,
        args,
        log: true,
    });

    const instance = await ethers.getContractAt(deploymentName, deployment.address);

    return (connect ? instance.connect(connect) : instance) as T;
}

export async function deployMock(contractName: string, connect?: Signer): Promise<MockContract> {
    const artifact = await deployments.getArtifact(contractName);
    const deployer = await ethers.getNamedSigner("deployer");
    return waffle.deployMockContract(connect ?? deployer, artifact.abi);
}

export async function hardhatIncreaseTime(secondsToIncrease: number): Promise<void> {
    await ethers.provider.send("evm_increaseTime", [secondsToIncrease]);
    await ethers.provider.send("evm_mine", []);
}
