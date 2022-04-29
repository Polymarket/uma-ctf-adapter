import { HardhatUserConfig } from "hardhat/config";
import { ChainId, getRemoteNetworkConfig, mnemonic, etherscanApiKey } from "./config";
import "./tasks";

import "hardhat-deploy";
// To make hardhat-waffle compatible with hardhat-deploy
// we have aliased hardhat-ethers to hardhat-ethers-deploy in package.json
import "@nomiclabs/hardhat-waffle";
import "hardhat-gas-reporter";
import "@typechain/hardhat";
import "solidity-coverage";

const accounts = {
    count: 10,
    initialIndex: 0,
    mnemonic,
    path: "m/44'/60'/0'/0",
};

const config: HardhatUserConfig = {
    defaultNetwork: "hardhat",
    namedAccounts: {
        deployer: 0, // Do not use this account for testing
        admin: 1,
    },
    networks: {
        hardhat: {
            initialBaseFeePerGas: 0, // Needed for solidity-coverage
            chainId: ChainId.hardhat,
            saveDeployments: false,
        },
        goerli: { accounts, ...getRemoteNetworkConfig("goerli") },
        kovan: { accounts, ...getRemoteNetworkConfig("kovan") },
        rinkeby: { accounts, ...getRemoteNetworkConfig("rinkeby") },
        ropsten: { accounts, ...getRemoteNetworkConfig("ropsten") },
        mumbai: { accounts, ...getRemoteNetworkConfig("mumbai"), gasPrice: 8000000000 },
        matic: { accounts, ...getRemoteNetworkConfig("matic"), gasPrice: 100000000000 },
        mainnet: { accounts, ...getRemoteNetworkConfig("mainnet") },
        shibuya: { accounts, ...getRemoteNetworkConfig("shibuya") },
        astarMainnet: { accounts, ...getRemoteNetworkConfig("astarMainnet") ,}
    },
    paths: {
        artifacts: "./artifacts",
        deployments: "./deployments",
        cache: "./cache",
        sources: "./contracts",
        tests: "./test",
    },
    solidity: {
        compilers: [
            {
                version: "0.8.0",
                settings: {
                    // https://hardhat.org/hardhat-network/#solidity-optimizer-support
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
        ],
    },
    typechain: {
        outDir: "typechain",
        target: "ethers-v5",
    },
    gasReporter: {
        currency: "USD",
        gasPrice: 100,
        excludeContracts: ["Mock", "ERC20"],
    },
    etherscan: {
        apiKey: etherscanApiKey,
    },
};

export default config;
