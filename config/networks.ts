import { infuraApiKey, maticVigilApiKey } from "./env";

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
    if (!maticVigilApiKey) {
        throw new Error("Please set your MATICVIGIL_API_KEY in a .env file");
    }

    const networkString = network === "matic" ? "mainnet" : "mumbai";
    return {
        url: `https://rpc-${networkString}.maticvigil.com/v1/${maticVigilApiKey}`,
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

export type RemoteChain = InfuraChain | MaticVigilChain | XDaiChain;
export const getRemoteNetworkConfig = (network: RemoteChain): { url: string; chainId: number } => {
    if (infuraChains.includes(network as InfuraChain)) return getInfuraConfig(network as InfuraChain);
    if (maticVigilChains.includes(network as MaticVigilChain)) return getMaticVigilConfig(network as MaticVigilChain);
    if (xDaiChains.includes(network as XDaiChain)) return getXDaiConfig(network as XDaiChain);
    throw Error("Unknown network");
};
