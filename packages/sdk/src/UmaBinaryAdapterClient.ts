import { JsonRpcSigner } from "@ethersproject/providers";
import { getAdapterContract } from "./UmaBinaryAdapterContract";


export class UmaBinaryAdapterClient {
    readonly chainID: number;
    readonly signer: JsonRpcSigner;

    constructor(signer: JsonRpcSigner, chainID: number) {
        this.signer = signer;
        this.chainID = chainID;
    }

    /**
     * 
     * @param questionID 
     * @param ancillaryData 
     * @param resolutionTime 
     * @param rewardToken 
     * @param reward 
     */
    async intializeQuestion(questionID: string, ancillaryData: string, resolutionTime: number, rewardToken: string, reward: number): Promise<void> {
        const adapterContract = await getAdapterContract(this.signer, this.chainID);
        await (await adapterContract.initializeQuestion(questionID, ancillaryData, resolutionTime, rewardToken, reward)).wait();
    }

    async requestResolutionData(questionID: string): Promise<void> {
        const adapterContract = await getAdapterContract(this.signer, this.chainID);
        await (await adapterContract.requestResolutionData(questionID)).wait();
    }

    async reportPayouts(questionID: string): Promise<void> {
        const adapterContract = await getAdapterContract(this.signer, this.chainID);
        await (await adapterContract.reportPayouts(questionID)).wait();
    }

    async emergencyReportPayouts(questionID: string, payouts: number[]): Promise<void> {
        const adapterContract = await getAdapterContract(this.signer, this.chainID);
        await (await adapterContract.emergencyReportPayouts(questionID, payouts)).wait();
    }
}