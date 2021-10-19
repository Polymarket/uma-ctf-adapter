export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0x132F6dd49DF50626e27685985B1c1B133e331b55";
        case 80001:
            return "0x4F8070c5a6dF56286F9b9A5B1A3AfeE437736567";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}