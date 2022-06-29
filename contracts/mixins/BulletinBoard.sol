// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Bulletin Board
/// @notice A registry containing ancillary data updates
abstract contract BulletinBoard {
    struct AncillaryDataUpdate {
        uint256 timestamp;
        bytes update;
    }

    /// @notice Mapping to an array of Ancillary data updates for questions
    mapping(bytes32 => AncillaryDataUpdate[]) public updates;

    /// @notice Emitted when an ancillary data update is posted
    event AncillaryDataUpdated(bytes32 indexed questionID, address indexed owner, bytes update);

    /// @notice Post an update for the question
    /// Anyone can post an update for any questionID, but users should only consider updates posted by the question creator
    /// @param questionID   - The unique questionID
    /// @param update       - The update for the question
    function postUpdate(bytes32 questionID, bytes memory update) external {
        bytes32 id = keccak256(abi.encode(questionID, msg.sender));
        updates[id].push(AncillaryDataUpdate({ timestamp: block.timestamp, update: update }));
    }

    /// @notice Gets all updates for a questionID and owner
    /// @param questionID   - The unique questionID
    /// @param owner        - The address of the question initializer
    function getUpdates(bytes32 questionID, address owner) public view returns (AncillaryDataUpdate[] memory) {
        return updates[keccak256(abi.encode(questionID, owner))];
    }

    /// @notice Gets the latest update for a questionID and owner
    /// @param questionID   - The unique questionID
    /// @param owner        - The address of the question initializer
    function getLatestUpdate(bytes32 questionID, address owner) external view returns (AncillaryDataUpdate memory) {
        AncillaryDataUpdate[] memory currentUpdates = getUpdates(questionID, owner);
        if (currentUpdates.length == 0) {
            return AncillaryDataUpdate({ timestamp: 0, update: "" });
        }
        return currentUpdates[currentUpdates.length - 1];
    }
}
