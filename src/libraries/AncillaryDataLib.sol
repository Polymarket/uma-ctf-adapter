// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

library AncillaryDataLib {

    string private constant initializerPrefix = ",initializer:";

    /// @notice Appends the initializer address to the ancillaryData
    /// @param initializer      - The initializer address
    /// @param ancillaryData    - The ancillary data
    function _appendAncillaryData(address initializer, bytes memory ancillaryData) internal pure returns (bytes memory) {
        return abi.encodePacked(ancillaryData, initializerPrefix, initializer);
    }
}
