// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Deployer } from "./Deployer.sol";
import { TestHelper } from "./TestHelper.sol";
import { USDC } from "./USDC.sol";

import { UmaCtfAdapter } from "src/UmaCtfAdapter.sol";
import { IFinder } from "src/interfaces/IFinder.sol";
import { IAddressWhitelist } from "src/interfaces/IAddressWhitelist.sol";

import { console2 as console } from "forge-std/console2.sol";

abstract contract AdapterHelper is TestHelper {
    address public admin = alice;
    UmaCtfAdapter public adapter;
    address public usdc;
    address public ctf;
    address public optimisticOracle;
    address public finder;
    address public whitelist;

    function setUp() public virtual {
        usdc = address(new USDC());
        ctf = Deployer.ConditionalTokens();
        optimisticOracle = Deployer.OptimisticOracleV2();

        whitelist = Deployer.AddressWhitelist();
        finder = Deployer.Finder();

        // Add USDC to whitelist
        IAddressWhitelist(whitelist).addToWhitelist(usdc);

        // Add Whitelist and Optimistic Oracle to Finder
        IFinder(finder).changeImplementationAddress("OptimisticOracleV2", optimisticOracle);
        IFinder(finder).changeImplementationAddress("CollateralWhitelist", whitelist);

        // Deploy adapter
        vm.prank(admin);
        adapter = new UmaCtfAdapter(ctf, finder);
    }
}
