export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xf1a3470Ea4943783d680ec2A8a05aE517684513D";
        case 80001:
            return "0x14aa3d1162821E21ef1C5a933F08467CD8cefAd5";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}