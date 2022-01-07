export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0x021dE777cf8C1a9d97bD93F4a587d7Fb7C982800";
        case 80001:
            return "0x66a1d8f7baff26081e7e90b33e1b143bd4934821";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}