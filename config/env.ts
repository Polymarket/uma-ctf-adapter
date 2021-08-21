import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";

dotenvConfig({ path: resolve(__dirname, "../.env") });

// Ensure that we have all the environment variables we need.
if (!process.env.MNEMONIC) {
    throw new Error("Please set your MNEMONIC in a .env file");
}

export const mnemonic: string = process.env.MNEMONIC;
export const infuraApiKey = process.env.INFURA_API_KEY;
export const maticVigilApiKey = process.env.MATICVIGIL_API_KEY;
