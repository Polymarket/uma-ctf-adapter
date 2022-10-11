// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Deployer } from "./Deployer.sol";
import { TestHelper } from "./TestHelper.sol";

import { UmaCtfAdapter } from "src/UmaCtfAdapter.sol";


abstract contract AdapterHelper is TestHelper {
    UmaCtfAdapter public adapter;
    address public usdc;
    address public ctf;

    function setUp() public virtual {
        // Deploy USDC, CTF, OptimisticOracle, Whitelist and finder
        // add usdc to whitelist
        // add OO and whitelist to finder

    }
}
