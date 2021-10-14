export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xf1a3470Ea4943783d680ec2A8a05aE517684513D";
        case 80001:
            return "0x1261d818a06771f3e3226Ff88a320EA4Ac5D5513";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}