export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xf1a3470Ea4943783d680ec2A8a05aE517684513D";
        case 80001:
            return "0xF24e9d400BCa737D825c88D8E09D4ad1d15beb6A";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}