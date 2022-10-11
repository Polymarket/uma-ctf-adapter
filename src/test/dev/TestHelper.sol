// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test, console2 as console, stdStorage, StdStorage, stdError } from "forge-std/Test.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";

abstract contract TestHelper is Test {
    mapping(address => mapping(address => uint256)) private balanceCheckpoints;

    address public alice = address(1);
    address public brian = address(2);
    address public carla = address(3);
    address public dylan = address(4);
    address public erica = address(5);
    address public frank = address(6);
    address public grace = address(7);
    address public henry = address(8);

    constructor() {
        vm.label(alice, "Alice");
        vm.label(brian, "Brian");
        vm.label(carla, "Carla");
        vm.label(dylan, "Dylan");
        vm.label(erica, "Erica");
        vm.label(frank, "Frank");
        vm.label(grace, "Grace");
        vm.label(henry, "Henry");
    }

    modifier with(address _account) {
        vm.startPrank(_account);
        _;
        vm.stopPrank();
    }

    function assertBalance(
        address _token,
        address _who,
        uint256 _amount
    ) internal {
        assertEq(ERC20(_token).balanceOf(_who), balanceCheckpoints[_token][_who] + _amount);
    }

    function checkpointBalance(address _token, address _who) internal {
        balanceCheckpoints[_token][_who] = balanceOf(_token, _who);
    }

    function balanceOf(address _token, address _who) internal view returns (uint256) {
        return ERC20(_token).balanceOf(_who);
    }

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        ERC20(_token).approve(_spender, _amount);
    }

    ///@dev msg.sender is the owner of the approved tokens
    function dealAndApprove(
        address _token,
        address _to,
        address _spender,
        uint256 _amount
    ) internal {
        deal(_token, _to, _amount);
        approve(_token, _spender, _amount);
    }

    function advance(uint256 _delta) internal {
        vm.roll(block.number + _delta);
    }
}
