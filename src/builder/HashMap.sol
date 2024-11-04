// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {List} from "./List.sol";

library HashMap {
    error KeyNotFound();

    struct Entry {
        bytes key;
        bytes value;
    }

    // NOTE: Now just use DynamicArray to help with Map use cases (could be optimized later)
    struct Map {
        List.DynamicArray entries;
    }

    function newMap() internal pure returns (Map memory) {
        return Map(List.newList());
    }

    function get(Map memory map, bytes memory key) internal pure returns (bytes memory) {
        for (uint256 i = 0; i < map.entries.length; ++i) {
            Entry memory entry = abi.decode(List.get(map.entries, i), (Entry));
            if (keccak256(entry.key) == keccak256(key)) {
                return entry.value;
            }
        }
        revert KeyNotFound();
    }

    function contains(Map memory map, bytes memory key) internal pure returns (bool) {
        for (uint256 i = 0; i < map.entries.length; ++i) {
            Entry memory entry = abi.decode(List.get(map.entries, i), (Entry));
            if (keccak256(entry.key) == keccak256(key)) {
                return true;
            }
        }
        return false;
    }

    function put(Map memory map, bytes memory key, bytes memory value) internal pure returns (Map memory) {
        Entry memory newEntry = Entry({key: key, value: value});
        for (uint256 i = 0; i < map.entries.length; ++i) {
            Entry memory entry = abi.decode(List.get(map.entries, i), (Entry));
            if (keccak256(entry.key) == keccak256(key)) {
                // Replace existing entry
                map.entries.bytesArray[i] = abi.encode(newEntry);
                return map;
            }
        }

        List.addItem(map.entries, abi.encode(newEntry));
        return map;
    }

    function remove(Map memory map, bytes memory key) internal pure returns (Map memory) {
        for (uint256 i = 0; i < map.entries.length; ++i) {
            Entry memory entry = abi.decode(List.get(map.entries, i), (Entry));
            if (keccak256(entry.key) == keccak256(key)) {
                List.remove(map.entries, i);
                return map;
            }
        }
        revert KeyNotFound();
    }

    function keys(Map memory map) internal pure returns (bytes[] memory) {
        bytes[] memory result = new bytes[](map.entries.length);
        for (uint256 i = 0; i < map.entries.length; ++i) {
            Entry memory entry = abi.decode(List.get(map.entries, i), (Entry));
            result[i] = entry.key;
        }
        return result;
    }

    // ========= Helper functions for common keys/values types =========
    function get(Map memory map, uint256 key) internal pure returns (bytes memory) {
        return get(map, abi.encode(key));
    }

    function contains(Map memory map, uint256 key) internal pure returns (bool) {
        return contains(map, abi.encode(key));
    }

    function put(Map memory map, uint256 key, bytes memory value) internal pure returns (Map memory) {
        return put(map, abi.encode(key), value);
    }

    function remove(Map memory map, uint256 key) internal pure returns (Map memory) {
        return remove(map, abi.encode(key));
    }

    function getUint256(Map memory map, bytes memory key) internal pure returns (uint256) {
        return abi.decode(get(map, key), (uint256));
    }

    function putUint256(Map memory map, bytes memory key, uint256 value) internal pure returns (Map memory) {
        return put(map, key, abi.encode(value));
    }

    function keysUint256(Map memory map) internal pure returns (uint256[] memory) {
        bytes[] memory keysBytes = keys(map);
        uint256[] memory keysUint = new uint256[](keysBytes.length);
        for (uint256 i = 0; i < keysBytes.length; ++i) {
            keysUint[i] = abi.decode(keysBytes[i], (uint256));
        }
        return keysUint;
    }

    function getDynamicArray(Map memory map, uint256 key) internal pure returns (List.DynamicArray memory) {
        return abi.decode(get(map, abi.encode(key)), (List.DynamicArray));
    }

    function putDynamicArray(Map memory map, uint256 key, List.DynamicArray memory value)
        internal
        pure
        returns (Map memory)
    {
        return put(map, abi.encode(key), abi.encode(value));
    }
}
