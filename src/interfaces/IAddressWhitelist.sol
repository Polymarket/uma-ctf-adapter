// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface IAddressWhitelist {
    function isOnWhitelist(address) external view returns (bool);
}

