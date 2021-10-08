export const getAdapterAddress = (chainID: number): string => {
    switch (chainID) {
        case 137:
            return "0xf1a3470Ea4943783d680ec2A8a05aE517684513D";
        case 80001:
            return "0xB312926d202e93A1Bd35a393E5922Cec843C2792";
        default:
            throw new Error(`Unsupported chainID: ${chainID}`);
    }
}