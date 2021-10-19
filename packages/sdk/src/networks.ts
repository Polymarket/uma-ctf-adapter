export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0x132F6dd49DF50626e27685985B1c1B133e331b55";
        case 80001:
            return "0x1261d818a06771f3e3226Ff88a320EA4Ac5D5513";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}