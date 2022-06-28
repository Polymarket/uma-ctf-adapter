// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Bulletin Board
/// @notice An onchain registry containing updates for questions
abstract contract BulletinBoard {
    struct Update {
        uint256 timestamp;
        bytes update;
    }

    /// @notice TODO natspec
    mapping(bytes32 => Update[]) public updates;

    /// @notice TODO natspec
    function postUpdate(bytes32 questionID, bytes memory update) external {
        bytes32 id = keccak256(abi.encode(questionID, msg.sender));
        updates[id].push(Update({ timestamp: block.timestamp, update: update }));
    }

    /// @notice TODO natspec
    function getUpdates(bytes32 questionID, address owner) public view returns (Update[] memory) {
        return updates[keccak256(abi.encode(questionID, owner))];
    }

    /// @notice TODO natspec
    function getLatestUpdate(bytes32 questionID, address owner) external view returns (Update memory) {
        Update[] memory currentUpdates = getUpdates(questionID, owner);
        return currentUpdates[currentUpdates.length - 1];
    }
}
