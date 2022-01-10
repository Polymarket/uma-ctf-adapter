export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xCB1822859cEF82Cd2Eb4E6276C7916e692995130";
        case 80001:
            return "0xCB1822859cEF82Cd2Eb4E6276C7916e692995130";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}