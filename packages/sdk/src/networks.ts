export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0x021dE777cf8C1a9d97bD93F4a587d7Fb7C982800";
        case 80001:
            return "0xf46A49FF838f19DCA55D547b7ED793a03989aF7b";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}