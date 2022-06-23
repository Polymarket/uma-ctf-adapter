// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @notice UMA Constants
/// @notice Constants used by UMA's Optimistic Oracle
library UmaConstants {
    /// @notice Unique query identifier for the Optimistic Oracle
    bytes32 public constant YesOrNoIdentifier = "YES_OR_NO_QUERY";

    /// @notice TODO natspec
    bytes32 public constant OptimisticOracle = "OptimisticOracle";

    /// @notice TODO natspec
    bytes32 public constant OptimisticOracleV2 = "OptimisticOracleV2";

    /// @notice TODO natspec
    bytes32 public constant CollateralWhitelist = "CollateralWhitelist";

    /// @notice TODO natspec
    uint256 public constant AncillaryDataLimit = 8139;
}
