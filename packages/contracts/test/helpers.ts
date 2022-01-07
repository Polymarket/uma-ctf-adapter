import { MockContract } from "ethereum-waffle";
import { BigNumber, Contract, Signer } from "ethers";
import { deployments, ethers, waffle } from "hardhat";

export interface QuestionData {
    resolutionTime: BigNumber;
    reward: BigNumber;
    proposalBond: BigNumber;
    settled: BigNumber;
    earlyResolutionTimestamp: BigNumber;
    earlyResolutionEnabled: boolean;
    resolutionDataRequested: boolean;
    resolved: boolean;
    paused: boolean;
    rewardToken: string;
    ancillaryData: string;
}

export interface Request {
    proposer: string;
    disputer: string;
    currency: string;
    settled: boolean;
    refundOnDispute: boolean;
    proposedPrice: number | BigNumber;
    resolvedPrice: BigNumber;
    expirationTime: number;
    reward: number;
    finalFee: number;
    bond: number;
    customLiveness: number;
}

export function createQuestionID(title: string, description: string): string {
    return ethers.utils.solidityKeccak256(["string", "string"], [title, description]);
}

export function createRandomQuestionID(): string {
    return createQuestionID(ethers.utils.randomBytes(5).toString(), ethers.utils.randomBytes(10).toString());
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
    reward: BigNumber,
    proposalBond: BigNumber,
    resolutionTime?: number,
    earlyExpiryEnabled?: boolean,
): Promise<string> {
    const questionID = createQuestionID(title, description);
    const defaultResolutionTime = Math.floor(new Date().getTime() / 1000) + 1000;

    const resTime = resolutionTime != null ? resolutionTime : defaultResolutionTime;
    const ancillaryData = createAncillaryData(title, description);
    const earlyExpiry = earlyExpiryEnabled === undefined ? false : earlyExpiryEnabled;
    await (
        await adapter.initializeQuestion(
            questionID,
            ancillaryData,
            resTime,
            rewardAddress,
            reward,
            proposalBond,
            earlyExpiry,
        )
    ).wait();

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

export function getMockRequest(): Request {
    const randAddress = ethers.Wallet.createRandom().address;
    return {
        proposer: randAddress,
        disputer: randAddress,
        currency: randAddress,
        settled: false,
        refundOnDispute: false,
        proposedPrice: 1,
        // resolved prices must be scaled by 1e18
        resolvedPrice: ethers.utils.parseEther("1"),
        expirationTime: 1,
        reward: 0,
        finalFee: 1,
        bond: 1,
        customLiveness: 1,
    };
}

export async function takeSnapshot(): Promise<string> {
    return ethers.provider.send("evm_snapshot", []);
}

export async function revertToSnapshot(snapshot: string): Promise<void> {
    await ethers.provider.send("evm_revert", [snapshot]);
}

export async function hardhatIncreaseTime(secondsToIncrease: number): Promise<void> {
    await ethers.provider.send("evm_increaseTime", [secondsToIncrease]);
    await ethers.provider.send("evm_mine", []);
}
