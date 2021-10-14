import { Contract } from "@ethersproject/contracts";
import { JsonRpcSigner, TransactionResponse } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import { BigNumber, ethers } from "ethers";
import adapterAbi from "./abi/adapterAbi";
import { QuestionData } from "./model";
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
     * @param proposalBond
     */
    public async initializeQuestion(questionID: string, title: string, description: string, outcomes: string[], resolutionTime: number, rewardToken: string, reward: BigNumber, proposalBond: BigNumber, overrides?: ethers.Overrides): Promise<void> {

        if (outcomes.length != 2) {
            throw new Error("Invalid outcome length! Must be 2!");
        }
        //dynamically generate ancillary data with binary resolution data appended
        const ancillaryData = createAncillaryData(title, description, outcomes);

        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.initializeQuestion(questionID, ancillaryData, resolutionTime, rewardToken, reward, proposalBond, overrides);
        } else {
            txn = await this.contract.initializeQuestion(questionID, ancillaryData, resolutionTime, rewardToken, reward, proposalBond);
        }

        console.log(`Initializing questionID: ${questionID} with: ${txn.hash}`);
        await txn.wait();
        console.log(`Question initialized!`)
    }

    /**
     * Fetch initialized question data 
     * @param questionID 
     * @returns 
     */
    public async getQuestionData(questionID: string): Promise<QuestionData> {
        const data = await this.contract.questions(questionID);
        const questionData: QuestionData = {
            ancillaryData: data.ancillaryData,
            resolutionTime: data.resolutionTime,
            rewardToken: data.rewardToken,
            reward: data.reward,
            proposalBond: data.proposalBond,
            resolutionDataRequested: data.resolutionDataRequested,
            resolved: data.resolved,
            paused: data.paused,
            settled: data.settled,
        }
        return questionData;
    }

    /**
     * Determines whether or not a questionID has been initialized
     * @param questionID 
     * @returns boolean
     */
    public async isQuestionIDInitialized(questionID: string): Promise<boolean> {
        return this.contract.isQuestionInitialized(questionID);
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
    public async requestResolutionData(questionID: string, overrides?: ethers.Overrides): Promise<void> {
        console.log(`Requesting resolution data from the Optimistic oracle...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.requestResolutionData(questionID, overrides);
        } else {
            txn = await this.contract.requestResolutionData(questionID);
        }
        await txn.wait()
        console.log(`Resolution data requested!`);
    }

    /**
     * Checks if a questionID is ready to be settled
     * @param questionID 
     * @returns boolean
     */
    public async readyToSettle(questionID: string): Promise<boolean> {
        return this.contract.readyToSettle(questionID)
    }

    /**
     * Settles/finalizes the OO price for a question
     * @param questionID 
     */
    public async settle(questionID: string, overrides?: ethers.Overrides): Promise<void> {
        console.log(`Settling the OO price for questionID: ${questionID}...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.settle(questionID, overrides);
        } else {
            txn = await this.contract.settle(questionID);
        }
        await txn.wait()
        console.log(`Question settled!`);
    }

    /**
     * Returns the expected payout value for a settled questionID
     * @param questionID 
     * @returns 
     */
    public async getExpectedPayouts(questionID: string): Promise<number[]> {
        console.log(`Fetching expected payout for: ${questionID}...`)
        const payout: number[] = await this.contract.getExpectedPayouts(questionID);
        return payout;
    }

    /**
     * Resolves a question by using the requested resolution data
     * @param questionID 
     */
    public async reportPayouts(questionID: string, overrides?: ethers.Overrides): Promise<void> {
        console.log(`Resolving question...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.reportPayouts(questionID, overrides);
        } else {
            txn = await this.contract.reportPayouts(questionID);
        }
        await txn.wait()
        console.log(`Question resolved!`);
    }

    /**
     * Pauses a question and prevents its resolution in an emergency
     * @param questionID 
     * @param overrides 
     */
    public async pauseQuestion(questionID: string, overrides?: ethers.Overrides): Promise<void> {
        console.log(`Pausing questionID: ${questionID}...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.pauseQuestion(questionID, overrides);
        } else {
            txn = await this.contract.pauseQuestion(questionID);
        }
        await txn.wait()
        console.log(`Question paused!`);
    }

    /**
     * Unpauses a question and allows it to be resolved
     * @param questionID 
     * @param overrides 
     */
    public async unpauseQuestion(questionID: string, overrides?: ethers.Overrides): Promise<void> {
        console.log(`Unpausing questionID: ${questionID}...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.unpauseQuestion(questionID, overrides);
        } else {
            txn = await this.contract.unpauseQuestion(questionID);
        }
        await txn.wait()
        console.log(`Question unpaused!`);
    }

    /**
     * Emergency report payouts
     * @param questionID 
     * @param payouts 
     */
    public async emergencyReportPayouts(questionID: string, payouts: number[], overrides?: ethers.Overrides): Promise<void> {
        console.log(`Emergency resolving question...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.emergencyReportPayouts(questionID, payouts, overrides);
        }
        else {
            txn = await this.contract.emergencyReportPayouts(questionID, payouts);
        }
        await txn.wait()
        console.log(`Question resolved!`);
    }
}