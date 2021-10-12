export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xf1a3470Ea4943783d680ec2A8a05aE517684513D";
        case 80001:
            return "0x25369B5B7Ad33DdEC97995F5b73AA2Bc55d49d88";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}