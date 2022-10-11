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
}
