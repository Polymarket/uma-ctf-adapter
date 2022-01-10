import { Contract } from "@ethersproject/contracts";
import { JsonRpcSigner, TransactionResponse, TransactionReceipt } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import { BigNumber, ethers } from "ethers";
import adapterAbi from "./abi/adapterAbi";
import { QuestionData } from "./model";
import { getAdapterAddress } from "./networks";
import { createAncillaryData } from "./utils";

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
     * @param questionID
     * @param title
     * @param description
     * @param outcomes
     * @param resolutionTime
     * @param rewardToken
     * @param reward
     * @param proposalBond
     * @param earlyResolutionEnabled
     */
    public async initializeQuestion(
        questionID: string,
        title: string,
        description: string,
        outcomes: string[],
        resolutionTime: number,
        rewardToken: string,
        reward: BigNumber,
        proposalBond: BigNumber,
        earlyResolutionEnabled: boolean,
        overrides?: ethers.Overrides,
    ): Promise<TransactionReceipt> {
        if (outcomes.length != 2) {
            throw new Error("Invalid outcome length! Must be 2!");
        }
        // Dynamically generate ancillary data with binary resolution data appended
        const ancillaryData = createAncillaryData(title, description, outcomes);

        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.initializeQuestion(
                questionID,
                ancillaryData,
                resolutionTime,
                rewardToken,
                reward,
                proposalBond,
                earlyResolutionEnabled,
                overrides,
            );
        } else {
            txn = await this.contract.initializeQuestion(
                questionID,
                ancillaryData,
                resolutionTime,
                rewardToken,
                reward,
                proposalBond,
                earlyResolutionEnabled,
            );
        }

        console.log(`Initializing questionID: ${questionID}...`);
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Question initialized!`);
        return receipt;
    }

    /**
     * Atomically prepares a condition on the CTF and initializes a question on the adapter
     * @param questionID
     * @param title
     * @param description
     * @param outcomes
     * @param resolutionTime
     * @param rewardToken
     * @param reward
     * @param proposalBond
     * @param earlyResolutionEnabled
     */
    public async prepareAndInitialize(
        questionID: string,
        title: string,
        description: string,
        outcomes: string[],
        resolutionTime: number,
        rewardToken: string,
        reward: BigNumber,
        proposalBond: BigNumber,
        earlyResolutionEnabled: boolean,
        overrides?: ethers.Overrides,
    ): Promise<TransactionReceipt> {
        if (outcomes.length != 2) {
            throw new Error("Invalid outcome length! Must be 2!");
        }
        // Dynamically generate ancillary data with binary resolution data appended
        const ancillaryData = createAncillaryData(title, description, outcomes);

        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.prepareAndInitialize(
                questionID,
                ancillaryData,
                resolutionTime,
                rewardToken,
                reward,
                proposalBond,
                earlyResolutionEnabled,
                overrides,
            );
        } else {
            txn = await this.contract.prepareAndInitialize(
                questionID,
                ancillaryData,
                resolutionTime,
                rewardToken,
                reward,
                proposalBond,
                earlyResolutionEnabled,
            );
        }

        console.log(`Preparing and initializing questionID: ${questionID}...`);
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Condition prepared and question initialized!`);
        return receipt;
    }

    /**
     * Fetch initialized question data
     * @param questionID
     * @returns
     */
    public async getQuestionData(questionID: string): Promise<QuestionData> {
        const data = await this.contract.questions(questionID);
        return {
            ancillaryData: data.ancillaryData,
            resolutionTime: data.resolutionTime,
            rewardToken: data.rewardToken,
            reward: data.reward,
            proposalBond: data.proposalBond,
            earlyResolutionEnabled: data.earlyResolutionEnabled,
            requestTimestamp: data.requestTimestamp,
            earlyRequestTimestamp: data.earlyRequestTimestamp,
            adminResolutionTimestamp: data.adminResolutionTimestamp,
            resolved: data.resolved,
            paused: data.paused,
            settled: data.settled,
        };
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
     * @param questionID
     */
    public async requestResolutionData(questionID: string, overrides?: ethers.Overrides): Promise<TransactionReceipt> {
        console.log(`Requesting resolution data from the Optimistic oracle...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.requestResolutionData(questionID, overrides);
        } else {
            txn = await this.contract.requestResolutionData(questionID);
        }
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Resolution data requested!`);
        return receipt;
    }

    /**
     * Checks if a questionID is ready to be settled
     * @param questionID
     * @returns boolean
     */
    public async readyToSettle(questionID: string): Promise<boolean> {
        return this.contract.readyToSettle(questionID);
    }

    /**
     * Settles/finalizes the OO price for a question
     * @param questionID
     */
    public async settle(questionID: string, overrides?: ethers.Overrides): Promise<TransactionReceipt> {
        console.log(`Settling the OO price for questionID: ${questionID}...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.settle(questionID, overrides);
        } else {
            txn = await this.contract.settle(questionID);
        }
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Question settled!`);
        return receipt;
    }

    /**
     * Returns the expected payout value for a settled questionID
     * @param questionID
     * @returns
     */
    public async getExpectedPayouts(questionID: string): Promise<number[]> {
        console.log(`Fetching expected payout for: ${questionID}...`);
        const payout: number[] = await this.contract.getExpectedPayouts(questionID);
        return payout;
    }

    /**
     * Resolves a question by using the requested resolution data
     * @param questionID
     */
    public async reportPayouts(questionID: string, overrides?: ethers.Overrides): Promise<TransactionReceipt> {
        console.log(`Resolving question...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.reportPayouts(questionID, overrides);
        } else {
            txn = await this.contract.reportPayouts(questionID);
        }
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Question resolved!`);
        return receipt;
    }

    /**
     * Pauses a question and prevents its resolution in an emergency
     * @param questionID
     * @param overrides
     */
    public async pauseQuestion(questionID: string, overrides?: ethers.Overrides): Promise<TransactionReceipt> {
        console.log(`Pausing questionID: ${questionID}...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.pauseQuestion(questionID, overrides);
        } else {
            txn = await this.contract.pauseQuestion(questionID);
        }
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Question paused!`);
        return receipt;
    }

    /**
     * Unpauses a question and allows it to be resolved
     * @param questionID
     * @param overrides
     */
    public async unpauseQuestion(questionID: string, overrides?: ethers.Overrides): Promise<TransactionReceipt> {
        console.log(`Unpausing questionID: ${questionID}...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.unpauseQuestion(questionID, overrides);
        } else {
            txn = await this.contract.unpauseQuestion(questionID);
        }
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Question unpaused!`);
        return receipt;
    }

    /**
     * Emergency report payouts
     * @param questionID
     * @param payouts
     */
    public async emergencyReportPayouts(
        questionID: string,
        payouts: number[],
        overrides?: ethers.Overrides,
    ): Promise<TransactionReceipt> {
        console.log(`Emergency resolving question...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.emergencyReportPayouts(questionID, payouts, overrides);
        } else {
            txn = await this.contract.emergencyReportPayouts(questionID, payouts);
        }
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Question resolved!`);
        return receipt;
    }

    /**
     * Flag question for emergency report resolution
     * @param questionID
     */
    public async flagQuestionForEmergencyResolution(
        questionID: string,
        overrides?: ethers.Overrides,
    ): Promise<TransactionReceipt> {
        console.log(`Flagging ${questionID} for emergency resolution...`);
        let txn: TransactionResponse;
        if (overrides != undefined) {
            txn = await this.contract.flagQuestionForEmergencyResolution(questionID, overrides);
        } else {
            txn = await this.contract.flagQuestionForEmergencyResolution(questionID);
        }
        console.log(`Transaction hash: ${txn.hash}`);
        const receipt: TransactionReceipt = await txn.wait();
        console.log(`Question flagged for emergency resolution!`);
        return receipt;
    }

    /**
     * Emergency report payouts
     * @param questionID
     * @returns
     */
    public async isQuestionFlaggedForEmergencyResolution(questionID: string): Promise<TransactionReceipt> {
        console.log(`Checking if question has been flagged for early resolution...`);
        const hasBeenFlaggedForEarlyResolutionQ = await this.contract.isQuestionFlaggedForEmergencyResolution(
            questionID,
        );
        return hasBeenFlaggedForEarlyResolutionQ;
    }
}
