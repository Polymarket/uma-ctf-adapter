// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface IAddressWhitelist {
    function addToWhitelist(address) external;

    function removeFromWhitelist(address) external;

    function isOnWhitelist(address) external view returns (bool);

    function getWhitelist() external view returns (address[] memory);
}

