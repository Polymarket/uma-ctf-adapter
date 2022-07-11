// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title AdapterErrors
/// @notice Errors for the CTF Adapter
library AdapterErrors {
    string public constant NotInitialized = "Adapter/not-initialized";

    string public constant NotFlagged = "Adapter/not-flagged";

    string public constant NotReadyToResolve = "Adapter/not-ready-to-resolve";

    string public constant AlreadyResolved = "Adapter/already-resolved";

    string public constant AlreadyInitialized = "Adapter/already-initialized";

    string public constant UnsupportedToken = "Adapter/unsupported-token";

    string public constant InvalidAncillaryData = "Adapter/invalid-ancillary-data";

    string public constant Flagged = "Adapter/flagged";

    string public constant SafetyPeriodNotPassed = "Adapter/safety-period-not-passed";

    string public constant NonBinaryPayouts = "Adapter/non-binary-payouts";

    string public constant Paused = "Adapter/paused";

    string public constant InvalidData = "Adapter/invalid-resolution-data";

    string public constant PriceUnavailable = "Adapter/price-unavailable";

    string public constant NotOptimisticOracle = "Adapter/not-oo";
}
