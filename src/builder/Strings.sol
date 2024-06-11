// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

library Strings {
    function stringEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function stringEqIgnoreCase(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(toLowerCase(a))) == keccak256(abi.encodePacked(toLowerCase(b)));
    }

    function toLowerCase(string memory str) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] >= 0x41 && strBytes[i] <= 0x5A) {
                strBytes[i] = bytes1(uint8(strBytes[i]) + 32);
            }
        }
        return string(strBytes);
    }
}
