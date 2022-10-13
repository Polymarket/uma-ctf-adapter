// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IAuth } from "../interfaces/IAuth.sol";

/// @title Auth
/// @notice Provides access control modifiers
abstract contract Auth is IAuth {
    /// @notice Auth
    mapping(address => uint256) public admins;

    modifier onlyAdmin() {
        if (admins[msg.sender] != 1) revert NotAdmin();
        _;
    }

    constructor() {
        admins[msg.sender] = 1;
    }

    /// @notice Adds an Admin
    /// @param admin - The address of the admin
    function addAdmin(address admin) external onlyAdmin {
        admins[admin] = 1;
        emit NewAdmin(msg.sender, admin);
    }

    /// @notice Removes an admin
    /// @param admin - The address of the admin to be removed
    function removeAdmin(address admin) external onlyAdmin {
        admins[admin] = 0;
        emit RemovedAdmin(msg.sender, admin);
    }

    /// @notice Renounces Admin privileges from the caller
    function renounceAdmin() external onlyAdmin {
        admins[msg.sender] = 0;
        emit RemovedAdmin(msg.sender, msg.sender);
    }
    
    /// @notice Checks if an address is an admin
    /// @param addr - The address to be checked
    function isAdmin(address addr) external view returns (bool) {
        return admins[addr] == 1;
    }
}
