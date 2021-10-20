export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0x132F6dd49DF50626e27685985B1c1B133e331b55";
        case 80001:
            return "0x3549A6e441f1EC5740d8A5941e5Afe111a40238A";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}