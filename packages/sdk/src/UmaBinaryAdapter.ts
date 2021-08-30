
import { JsonRpcSigner } from "@ethersproject/abstract-signer";

class UmaBinaryAdapter {
    readonly chainID: number;
    readonly signer: JsonRpcSigner;
}