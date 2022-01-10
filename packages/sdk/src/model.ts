import { BigNumber } from "ethers";

export interface QuestionData {
    resolutionTime: BigNumber;
    reward: BigNumber;
    proposalBond: BigNumber;
    settled: BigNumber;
    requestTimestamp: BigNumber;
    earlyRequestTimestamp: BigNumber;
    adminResolutionTimestamp: BigNumber;
    earlyResolutionEnabled: boolean;
    resolved: boolean;
    paused: boolean;
    rewardToken: string;
    ancillaryData: string;
}