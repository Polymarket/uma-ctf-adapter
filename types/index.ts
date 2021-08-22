import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";

export interface Signers {
    deployer: SignerWithAddress;
    admin: SignerWithAddress;
    tester: SignerWithAddress;
}
