import { ethers } from "ethers";
import { YES_NO_RESOLUTION_DATA } from "./constants";

/**
 * Creates a 32 byte questionID hash from the question title and description
 * 
 * @param title 
 * @param description 
 * @returns 
 */
export const createQuestionID = (title: string, description: string): string => {
    return ethers.utils.solidityKeccak256(["string", "string"], [title, description]);
}

/**
 * Creates the ancillary data used to resolve questions
 * Automatically appends resolution request information
 * 
 * @param title 
 * @param description 
 * @returns 
 */
export const createAncillaryData = (title: string, description: string): Uint8Array => {
    return ethers.utils.toUtf8Bytes(`title: ${title} description: ${description} uma_resolution_data: ${YES_NO_RESOLUTION_DATA}`);
}