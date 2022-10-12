// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Vm } from "forge-std/Vm.sol";

library Deployer {

    Vm public constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function _deployCode(string memory _what) internal returns (address addr) {
        return _deployCode(_what, "");
    }

    function _deployCode(string memory _what, bytes memory _args) internal returns (address addr) {
        bytes memory bytecode = abi.encodePacked(vm.getCode(_what), _args);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function ConditionalTokens() public returns (address) {
        address deployment = _deployCode("artifacts/ConditionalTokens.json");
        vm.label(deployment, "ConditionalTokens");
        return deployment;
    }

    function OptimisticOracleV2() public returns (address) {
        address deployment = _deployCode("artifacts/OptimisticOracleV2.json");
        vm.label(deployment, "OptimisticOracleV2");
        return deployment;
    }

    function AddressWhitelist() public returns (address) {
        address deployment = _deployCode("artifacts/AddressWhitelist.json");
        vm.label(deployment, "AddressWhitelist");
        return deployment;
    }

    function Finder() public returns (address) {
        address deployment = _deployCode("artifacts/Finder.json");
        vm.label(deployment, "Finder");
        return deployment;
    }
}
