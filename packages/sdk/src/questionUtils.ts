import { ethers } from "ethers";
import { YES_NO_RESOLUTION_DATA } from "./constants";

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