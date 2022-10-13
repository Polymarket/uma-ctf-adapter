// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @notice Stub contract used to mock UMA's Voting.sol(or OracleChildTunnel on Polygon)
contract OracleStub {

    bool public priceExists;
    int256 public price;
    
    function requestPrice(
        bytes32,
        uint256,
        bytes memory
    ) public {
        // no-op
    }

    function hasPrice(
        bytes32,
        uint256,
        bytes memory
    ) public view returns (bool) {
        return priceExists;
    }

    function getPrice(
        bytes32,
        uint256,
        bytes memory
    ) public view returns (int256) {
        return price;
    }

    function setPriceExists(bool _priceExists) public {
        priceExists = _priceExists;
    }

    function setPrice(int256 _price) public {
        price = _price;
    }
}