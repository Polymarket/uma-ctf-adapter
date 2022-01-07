import { BigNumber } from "ethers";

export interface QuestionData {
    ancillaryData: string;
    resolutionTime: number;
    rewardToken: string;
    reward: BigNumber;
    proposalBond: BigNumber;
    earlyResolutionEnabled: boolean;
    earlyResolutionTimestamp: number;
    resolutionDataRequested: boolean;
    resolved: boolean;
    paused: boolean;
    settled: number;
}