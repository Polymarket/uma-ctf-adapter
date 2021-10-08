import { Contract } from "@ethersproject/contracts";
import { JsonRpcSigner, TransactionResponse } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import adapterAbi from "./abi/adapterAbi";
import { getAdapterAddress } from "./networks";
import { createAncillaryData } from "./questionUtils";


export class UmaBinaryAdapterClient {
    readonly chainID: number;
    readonly signer: JsonRpcSigner | Wallet;
    readonly contract: Contract;

    constructor(signer: JsonRpcSigner | Wallet, chainID: number) {
        this.signer = signer;
        this.chainID = chainID;
        this.contract = new Contract(getAdapterAddress(this.chainID), adapterAbi, this.signer);
    }

    /**
     * Initializes a question on the adapter contract
     * 
     * @param title 
     * @param description 
     * @param resolutionTime 
     * @param rewardToken 
     * @param reward 
     */
    public async initializeQuestion(questionID: string, title: string, description: string, resolutionTime: number, rewardToken: string, reward: number): Promise<void> {
        //generate ancillary data with binary resolution data appended
        const ancillaryData = createAncillaryData(title, description);

        const txn: TransactionResponse = await this.contract.initializeQuestion(questionID, ancillaryData, resolutionTime, rewardToken, reward);
        console.log(`Initializing questionID: ${questionID} with: ${txn.hash}`);
        await txn.wait();
        console.log(`Question initialized!`)
    }

    /**
     * Updates an already initialized Question
     * 
     * @param questionID 
     * @param ancillaryData 
     * @param resolutionTime 
     * @param rewardToken 
     * @param reward 
     */
    public async updateQuestion(questionID: string, ancillaryData: Uint8Array, resolutionTime: number, rewardToken: string, reward: number): Promise<void> {
        const txn: TransactionResponse = await this.contract.updateQuestion(questionID, ancillaryData, resolutionTime, rewardToken, reward);
        console.log(`Updating question! Hash: ${txn.hash}`)
        await txn.wait();
        console.log(`Updated question!`)
    }

    /**
     * Checks if a questionID can start the UMA resolution process
     * @param questionID 
     * @returns boolean
     */
    public async readyToRequestResolution(questionID: string): Promise<boolean> {
        return this.contract.readyToRequestResolution(questionID);
    }

    /**
     * Requests question resolution data from UMA
     * 
     * @param questionID 
     */
    public async requestResolutionData(questionID: string): Promise<void> {
        console.log(`Requesting resolution data from the Optimistic oracle...`);
        const txn: TransactionResponse = await this.contract.requestResolutionData(questionID);
        await txn.wait()
        console.log(`Resolution data requested!`);
    }

    /**
     * Checks if a questionID is ready to be resolved
     * @param questionID 
     * @returns boolean
     */
    public async readyToReportPayouts(questionID: string): Promise<boolean> {
        return this.contract.readyToReportPayouts(questionID)
    }

    /**
     * Resolves a question by using the requested resolution data
     * @param questionID 
     */
    public async reportPayouts(questionID: string): Promise<void> {
        console.log(`Resolving question...`);
        const txn: TransactionResponse = await this.contract.reportPayouts(questionID);
        await txn.wait()
        console.log(`Question resolved!`);
    }

    /**
     * Emergency report payouts
     * @param questionID 
     * @param payouts 
     */
    public async emergencyReportPayouts(questionID: string, payouts: number[]): Promise<void> {
        console.log(`Emergency resolving question...`);
        const txn: TransactionResponse = await this.contract.emergencyReportPayouts(questionID, payouts);
        await txn.wait()
        console.log(`Question resolved!`);
    }
}