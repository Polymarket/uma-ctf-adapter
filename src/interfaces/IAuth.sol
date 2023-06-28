// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IAuthEE {
    error NotAdmin();

    /// @notice Emitted when a new admin is added
    event NewAdmin(address indexed admin, address indexed newAdminAddress);

    /// @notice Emitted when an admin is removed
    event RemovedAdmin(address indexed admin, address indexed removedAdmin);
}

interface IAuth is IAuthEE {
    function isAdmin(address) external view returns (bool);

    function addAdmin(address) external;

    function removeAdmin(address) external;

    function renounceAdmin() external;
}
