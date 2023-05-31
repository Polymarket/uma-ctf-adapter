// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

struct AncillaryDataUpdate {
    uint256 timestamp;
    bytes update;
}

interface IBulletinBoardEE {
    /// @notice Emitted when an ancillary data update is posted
    event AncillaryDataUpdated(bytes32 indexed questionID, address indexed owner, bytes update);    
}

interface IBulletinBoard is IBulletinBoardEE {
    function postUpdate(bytes32 questionID, bytes memory update) external;
    
    function getUpdates(bytes32 questionID, address owner) external view returns (AncillaryDataUpdate[] memory);
    
    function getLatestUpdate(bytes32 questionID, address owner) external view returns (AncillaryDataUpdate memory);
}
