export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0x5df4AFB8530e4Cf1Ec64dC31B28994B72665Aa5f";
        case 80001:
            return "0x5df4AFB8530e4Cf1Ec64dC31B28994B72665Aa5f";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}