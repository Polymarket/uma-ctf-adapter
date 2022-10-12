// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AdapterHelper } from "./dev/AdapterHelper.sol";

import { IAddressWhitelist } from "src/interfaces/IAddressWhitelist.sol";

contract UMaCtfAdapterTest is AdapterHelper {

    function testSetup() public {
        assertEq(whitelist, address(adapter.collateralWhitelist()));
        assertEq(ctf, address(adapter.ctf()));
        assertEq(optimisticOracle, address(adapter.optimisticOracle()));
        assertTrue(IAddressWhitelist(whitelist).isOnWhitelist(usdc));
    }

}