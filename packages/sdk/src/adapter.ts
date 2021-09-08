import { Contract } from "@ethersproject/contracts";
import { JsonRpcSigner, TransactionResponse } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import adapterAbi from "./abi/adapterAbi";
import { getAdapterAddress } from "./networks";
import { createAncillaryData, createQuestionID } from "./questionUtils";


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
    public async initializeQuestion(title: string, description: string, resolutionTime: number, rewardToken: string, reward: number): Promise<void> {
        const questionID = createQuestionID(title, description);
        const ancillaryData = createAncillaryData(title, description);

        const txn: TransactionResponse = await this.contract.initializeQuestion(questionID, ancillaryData, resolutionTime, rewardToken, reward);
        console.log(`Initializing question with: ${txn.hash}`);
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

    public async requestResolutionData(questionID: string): Promise<void> {
        console.log(`Requesting resolution data from the Optimistic oracle...`);
        const txn: TransactionResponse = await this.contract.requestResolutionData(questionID);
        await txn.wait()
        console.log(`resolution data requested!`);
    }

    public async reportPayouts(questionID: string): Promise<void> {
        console.log(`Resolving question...`);
        const txn: TransactionResponse = await this.contract.reportPayouts(questionID);
        await txn.wait()
        console.log(`Question resolved!`);
    }

    public async emergencyReportPayouts(questionID: string, payouts: number[]): Promise<void> {
        console.log(`Emergency resolving question...`);
        const txn: TransactionResponse = await this.contract.emergencyReportPayouts(questionID, payouts);
        await txn.wait()
        console.log(`Question resolved!`);
    }
}