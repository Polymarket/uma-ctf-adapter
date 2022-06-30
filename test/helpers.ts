import { MockContract } from "ethereum-waffle";
import { BigNumber, Contract, Signer } from "ethers";
import { deployments, ethers, waffle } from "hardhat";
import { JsonRpcSigner } from "@ethersproject/providers";

export interface RequestSettings {
    eventBased: boolean;
    refundOnDispute: boolean;
    callbackOnPriceProposed: boolean;
    callbackOnPriceDisputed: boolean;
    callbackOnPriceSettled: boolean;
    bond: number;
    customLiveness: number;
}

export interface Request {
    proposer: string;
    disputer: string;
    currency: string;
    settled: boolean;
    requestSettings: RequestSettings;
    proposedPrice: number | BigNumber;
    resolvedPrice: BigNumber;
    expirationTime: number;
    reward: number;
    finalFee: number;
}

export function createAncillaryData(title: string, description: string): Uint8Array {
    return ethers.utils.toUtf8Bytes(`q: ${title}d: ${description}`);
}

export async function initializeQuestion(
    adapter: Contract,
    title: string,
    description: string,
    rewardAddress: string,
    reward: BigNumber,
    proposalBond: BigNumber,
): Promise<string> {
    const ancillaryData = createAncillaryData(title, description);
    await (await adapter.initializeQuestion(ancillaryData, rewardAddress, reward, proposalBond)).wait();
    const expectedQuestionID = await adapter.getQuestionID(ancillaryData);
    return expectedQuestionID;
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
    const settings: RequestSettings = {
        eventBased: true,
        refundOnDispute: true,
        callbackOnPriceProposed: false,
        callbackOnPriceDisputed: false,
        callbackOnPriceSettled: false,
        bond: 1,
        customLiveness: 1,
    };

    return {
        proposer: randAddress,
        disputer: ethers.constants.AddressZero,
        currency: randAddress,
        settled: false,
        requestSettings: settings,
        proposedPrice: 1,
        // resolved prices must be scaled by 1e18
        resolvedPrice: ethers.utils.parseEther("1"),
        expirationTime: 1,
        reward: 0,
        finalFee: 1,
    };
}

export async function hardhatIncreaseTime(secondsToIncrease: number): Promise<void> {
    await ethers.provider.send("evm_increaseTime", [secondsToIncrease]);
    await ethers.provider.send("evm_mine", []);
}

export async function hardhatImpersonate(address: string): Promise<void> {
    await ethers.provider.send("hardhat_impersonateAccount", [address]);
    await ethers.provider.send("hardhat_setBalance", [address, "0x100000000000000000000000000"]);
}

export async function getSignerForAddress(address: string): Promise<JsonRpcSigner> {
    await hardhatImpersonate(address);
    const signer = await ethers.provider.getSigner(address);
    return signer;
}
