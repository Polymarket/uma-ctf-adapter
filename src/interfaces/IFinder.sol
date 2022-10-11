// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/**
 * @title Provides addresses of the live contracts implementing certain interfaces.
 * @dev Examples are the Oracle or Store interfaces.
 */
interface IFinder {

    /**
     * @notice Gets the address of the contract that implements the given `interfaceName`.
     * @param interfaceName queried interface.
     * @return implementationAddress address of the deployed contract that implements the interface.
     */
    function getImplementationAddress(bytes32 interfaceName) external view returns (address);
}
