import { infuraApiKey } from "./env";

export enum ChainId {
    ganache = 1337,
    goerli = 5,
    hardhat = 31337,
    kovan = 42,
    mainnet = 1,
    matic = 137,
    mumbai = 80001,
    rinkeby = 4,
    ropsten = 3,
    xdai = 100,
    shibuya = 81,
    astarMainnet = 592,
}

// Delegate requests for a network config to a provider specific function based on which networks they serve

// Ethereum
const infuraChains = ["goerli", "kovan", "mainnet", "rinkeby", "ropsten"] as const;
type InfuraChain = typeof infuraChains[number];
const getInfuraConfig = (network: InfuraChain): { url: string; chainId: number } => {
    if (!process.env.INFURA_API_KEY) {
        throw new Error("Please set your INFURA_API_KEY in a .env file");
    }
    return {
        url: `https://${network}.infura.io/v3/${infuraApiKey}`,
        chainId: ChainId[network],
    };
};

// Matic
const maticVigilChains = ["matic", "mumbai"] as const;
type MaticVigilChain = typeof maticVigilChains[number];
const getMaticVigilConfig = (network: MaticVigilChain): { url: string; chainId: number } => {
    if (!process.env.INFURA_API_KEY) {
        throw new Error("Please set your INFURA_API_KEY in a .env file");
    }

    const networkString = network === "matic" ? "mainnet" : "mumbai";
    return {
        url: `https://polygon-${networkString}.infura.io/v3/${infuraApiKey}`,
        chainId: ChainId[network],
    };
};

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const getPolygonInfuraChain = (network: MaticVigilChain): { url: string; chainId: number } => {
    if (!process.env.INFURA_API_KEY) {
        throw new Error("Please set your INFURA_API_KEY in a .env file");
    }
    const networkString = network === "matic" ? "mainnet" : "mumbai";
    return {
        url: `https://polygon-${networkString}.infura.io/v3/${infuraApiKey}`,
        chainId: ChainId[network],
    };
};

// xDai
const xDaiChains = ["xdai"] as const;
type XDaiChain = typeof xDaiChains[number];
const getXDaiConfig = (network: XDaiChain): { url: string; chainId: number } => {
    return {
        url: `https://rpc.xdaichain.com/`,
        chainId: ChainId[network],
    };
};

// Astar
const astarChains = ["shibuya", "astarMainnet"] as const;
type AstarChain = typeof astarChains[number];
const getAstarConfig = (network: AstarChain): { url: string; chainId: number } => {
    if (network == "astarMainnet") {
        return {
            url: `https://astar.api.onfinality.io/public`,
            chainId: ChainId[network],
        };
    } else if (network == "shibuya") {
        return {
            url: `https://rpc.shibuya.astar.network:8545`,
            chainId: ChainId[network],
        };
    } else {
        throw new Error("Please check the chain name");
    }
};

export type RemoteChain = InfuraChain | MaticVigilChain | XDaiChain | AstarChain;
export const getRemoteNetworkConfig = (network: RemoteChain): { url: string; chainId: number } => {
    if (infuraChains.includes(network as InfuraChain)) return getInfuraConfig(network as InfuraChain);
    if (maticVigilChains.includes(network as MaticVigilChain)) return getMaticVigilConfig(network as MaticVigilChain);
    if (xDaiChains.includes(network as XDaiChain)) return getXDaiConfig(network as XDaiChain);
    if (astarChains.includes(network as AstarChain)) return getAstarConfig(network as AstarChain);
    throw Error("Unknown network");
};

