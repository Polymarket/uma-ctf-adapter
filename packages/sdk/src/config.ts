const MATIC_ADAPTER = "0xf1a3470Ea4943783d680ec2A8a05aE517684513D";
const MUMBAI_ADAPTER = "0xf05f1999E04828DaE6eBE04A5F041190DF32e5A9";


export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return MATIC_ADAPTER;
        case 80001:
            return MUMBAI_ADAPTER;
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}


