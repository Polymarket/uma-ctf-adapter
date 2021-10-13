export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xf1a3470Ea4943783d680ec2A8a05aE517684513D";
        case 80001:
            return "0x4F8070c5a6dF56286F9b9A5B1A3AfeE437736567";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}