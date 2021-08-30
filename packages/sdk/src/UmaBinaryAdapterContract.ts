import { Contract } from "@ethersproject/contracts";
import { Signer } from "@ethersproject/abstract-signer";
import adapterAbi from "./abi/adapterAbi";

import { getAdapterAddress } from "./config";

export const getAdapterContract = (signer: Signer, chainId: number): Contract => {
    return new Contract(getAdapterAddress(chainId), adapterAbi, signer);
};
