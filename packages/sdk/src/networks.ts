export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0x7336e3e181b0E615dD9Cc3e35197593363Bd6407";
        case 80001:
            return "0x7336e3e181b0E615dD9Cc3e35197593363Bd6407";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}