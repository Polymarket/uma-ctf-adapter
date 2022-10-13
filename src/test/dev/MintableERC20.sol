// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MintableERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
