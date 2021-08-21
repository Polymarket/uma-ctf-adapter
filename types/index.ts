import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

export interface Signers {
    deployer: SignerWithAddress;
    admin: SignerWithAddress;
    tester: SignerWithAddress;
}
