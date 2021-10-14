import { BigNumber } from "ethers";

export interface QuestionData {
    ancillaryData: string;
    resolutionTime: number;
    rewardToken: string;
    reward: BigNumber;
    proposalBond: BigNumber;
    resolutionDataRequested: boolean;
    resolved: boolean;
    paused: boolean;
    settled: number;
}