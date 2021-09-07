export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xf1a3470Ea4943783d680ec2A8a05aE517684513D";
        case 80001:
            return "0x46546DF11921a781c2e44C370163263E15b739A9";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}