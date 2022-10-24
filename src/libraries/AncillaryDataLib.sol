// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

library AncillaryDataLib {

    string private constant initializerPrefix = ",initializer:";

    /// @notice Appends the initializer address to the ancillaryData
    /// @param initializer      - The initializer address
    /// @param ancillaryData    - The ancillary data
    function _appendAncillaryData(address initializer, bytes memory ancillaryData) internal pure returns (bytes memory) {
        return abi.encodePacked(ancillaryData, initializerPrefix, _toUtf8BytesAddress(initializer));
    }

    /// @notice Returns a UTF8-encoded address
    /// Source: UMA Protocol's AncillaryDataLib
    /// https://github.com/UMAprotocol/protocol/blob/9967e70e7db3f262fde0dc9d89ea04d4cd11ed97/packages/core/contracts/common/implementation/AncillaryData.sol
    /// Will return address in all lower case characters and without the leading 0x.
    /// @param addr - The address to encode.
    function _toUtf8BytesAddress(address addr) internal pure returns (bytes memory) {
        return
            abi.encodePacked(_toUtf8Bytes32Bottom(bytes32(bytes20(addr)) >> 128), bytes8(_toUtf8Bytes32Bottom(bytes20(addr))));
    }

    /// @notice Converts the bottom half of a bytes32 input to hex in a highly gas-optimized way.
    /// Source: the brilliant implementation at https://gitter.im/ethereum/solidity?at=5840d23416207f7b0ed08c9b.
    function _toUtf8Bytes32Bottom(bytes32 bytesIn) private pure returns (bytes32) {
        unchecked {
            uint256 x = uint256(bytesIn);

            // Nibble interleave
            x = x & 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;
            x = (x | (x * 2**64)) & 0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff;
            x = (x | (x * 2**32)) & 0x00000000ffffffff00000000ffffffff00000000ffffffff00000000ffffffff;
            x = (x | (x * 2**16)) & 0x0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff;
            x = (x | (x * 2**8)) & 0x00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff;
            x = (x | (x * 2**4)) & 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;

            // Hex encode
            uint256 h = (x & 0x0808080808080808080808080808080808080808080808080808080808080808) / 8;
            uint256 i = (x & 0x0404040404040404040404040404040404040404040404040404040404040404) / 4;
            uint256 j = (x & 0x0202020202020202020202020202020202020202020202020202020202020202) / 2;
            x = x + (h & (i | j)) * 0x27 + 0x3030303030303030303030303030303030303030303030303030303030303030;

            // Return the result.
            return bytes32(x);
        }
    }
}
