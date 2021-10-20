export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xbBfc55F7E092BC48C1aff0aa09186D94EDBD9f9A";
        case 80001:
            return "0x3549A6e441f1EC5740d8A5941e5Afe111a40238A";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}