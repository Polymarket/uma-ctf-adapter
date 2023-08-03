// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

/// @title TransferHelper
/// @notice Helper library to transfer tokens
library TransferHelper {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @param token    - The contract address of the token to be transferred
    /// @param from     - The originating address from which the tokens will be transferred
    /// @param to       - The destination address of the transfer
    /// @param amount   - The amount to be transferred
    function _transferFromERC20(address token, address from, address to, uint256 amount) internal {
        SafeTransferLib.safeTransferFrom(ERC20(token), from, to, amount);
    }

    /// @notice Transfers tokens from the current address to the given destination
    /// @param token    - The contract address of the token to be transferred
    /// @param to       - The destination address of the transfer
    /// @param amount   - The amount to be transferred
    function _transfer(address token, address to, uint256 amount) internal {
        SafeTransferLib.safeTransfer(ERC20(token), to, amount);
    }
}
