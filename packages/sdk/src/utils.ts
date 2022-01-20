import { ethers } from "ethers";


/**
 * Build resolution data string to be passed into the UMA Optimistic Oracle
 * E.g [Yes, No] => `p1: 0, p2: 1. Where p2 corresponds to Yes, p1 to a No`
 * @param outcomes 
 * @returns 
 */
export const buildResolutionData = (outcomes: string[]): string => {
    return `p1: 0, p2: 1, p3: 0.5. Where p2 corresponds to ${outcomes[0]}, p1 to a ${outcomes[1]}, p3 to unknown`;
}

export const OUTCOME_REGEX = /Where p2 corresponds to (\w+), p1 to a (\w+)/;

export const extractOutcomes = (ancillaryDataString: string): string[] | null => {
    const matched = ancillaryDataString.match(OUTCOME_REGEX);
    if (matched && matched.length == 3) {
        const outcomes: string[] = [matched[1], matched[2]];
        return outcomes;
    }
    return null;
}


/**
 * Creates the ancillary data used to resolve questions
 * Appends resolution request information
 * 
 * @param title 
 * @param description
 * @param outcomes 
 * @returns 
 */
export const createAncillaryData = (title: string, description: string, outcomes: string[]): Uint8Array => {
    return ethers.utils.toUtf8Bytes(`q: title: ${title}, description: ${description} res_data: ${buildResolutionData(outcomes)}`);
}