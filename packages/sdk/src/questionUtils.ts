import { ethers } from "ethers";


/**
 * Build resolution data string to be passed into the UMA Optimistic Oracle
 * E.g [Yes, No] => `p1: 0, p2: 1. Where p2 corresponds to Yes, p1 to a No`
 * @param outcomes 
 * @returns 
 */
export const buildResolutionData = (outcomes: string[]): string => {
    return `p1: 0, p2: 1. Where p2 corresponds to ${outcomes[0]}, p1 to a ${outcomes[1]}`;
}


/**
 * Creates the ancillary data used to resolve questions
 * Automatically appends resolution request information
 * 
 * @param title 
 * @param description
 * @param outcomes 
 * @returns 
 */
export const createAncillaryData = (title: string, description: string, outcomes: string[]): Uint8Array => {
    const resData = buildResolutionData(outcomes);
    return ethers.utils.toUtf8Bytes(`title: ${title} description: ${description} uma_resolution_data: ${resData}`);
}