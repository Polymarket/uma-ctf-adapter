// eslint-disable @typescript-eslint/no-explicit-any
import { Fixture } from "ethereum-waffle";

import { Signers } from ".";

declare module "mocha" {
    export interface Context {
        loadFixture: <T>(fixture: Fixture<T>) => Promise<T>;
        signers: Signers;
    }
}
