// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Actions} from "./Actions.sol";

library List {
    error IndexOutOfBound();

    struct DynamicArray {
        bytes[] bytesArray;
        uint256 length;
    }

    function newList() internal pure returns (DynamicArray memory) {
        return DynamicArray(new bytes[](0), 0);
    }

    function toArray(DynamicArray memory list) internal pure returns (bytes[] memory) {
        bytes[] memory result = new bytes[](list.length);
        for (uint256 i = 0; i < list.length; ++i) {
            result[i] = list.bytesArray[i];
        }
        return result;
    }

    function addItem(DynamicArray memory list, bytes memory item) internal pure returns (DynamicArray memory) {
        if (list.length >= list.bytesArray.length) {
            bytes[] memory newBytesArray = new bytes[](list.bytesArray.length * 2 + 1);
            for (uint256 i = 0; i < list.length; ++i) {
                newBytesArray[i] = list.bytesArray[i];
            }
            list.bytesArray = newBytesArray;
        }

        list.bytesArray[list.length] = item;
        list.length++;
        return list;
    }

    function get(DynamicArray memory list, uint256 index) internal pure returns (bytes memory) {
        if (index >= list.length) revert IndexOutOfBound();
        return list.bytesArray[index];
    }

    function remove(DynamicArray memory list, uint256 index) internal pure {
        if (index >= list.length) revert IndexOutOfBound();
        for (uint256 i = index; i < list.length - 1; ++i) {
            list.bytesArray[i] = list.bytesArray[i + 1];
        }
        list.length--;
    }

    function indexOf(DynamicArray memory list, bytes memory item) internal pure returns (int256) {
        for (uint256 i = 0; i < list.length; ++i) {
            if (keccak256(list.bytesArray[i]) == keccak256(item)) {
                return int256(i);
            }
        }
        return -1;
    }

    function contains(DynamicArray memory list, bytes memory item) internal pure returns (bool) {
        return indexOf(list, item) != -1;
    }

    // Struct APIs

    // === QuarkOperations ===

    function addQuarkOperation(DynamicArray memory list, IQuarkWallet.QuarkOperation memory operation)
        internal
        pure
        returns (DynamicArray memory)
    {
        return addItem(list, abi.encode(operation));
    }

    function getQuarkOperation(DynamicArray memory list, uint256 index)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory)
    {
        return abi.decode(get(list, index), (IQuarkWallet.QuarkOperation));
    }

    function toQuarkOperationArray(DynamicArray memory list)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation[] memory)
    {
        IQuarkWallet.QuarkOperation[] memory result = new IQuarkWallet.QuarkOperation[](list.length);
        for (uint256 i = 0; i < list.length; ++i) {
            result[i] = abi.decode(list.bytesArray[i], (IQuarkWallet.QuarkOperation));
        }
        return result;
    }

    function indexOf(DynamicArray memory list, IQuarkWallet.QuarkOperation memory item)
        internal
        pure
        returns (int256)
    {
        return indexOf(list, abi.encode(item));
    }

    function contains(DynamicArray memory list, IQuarkWallet.QuarkOperation memory item) internal pure returns (bool) {
        return contains(list, abi.encode(item));
    }

    // === Action ===

    function addAction(DynamicArray memory list, Actions.Action memory action)
        internal
        pure
        returns (DynamicArray memory)
    {
        return addItem(list, abi.encode(action));
    }

    function getAction(DynamicArray memory list, uint256 index) internal pure returns (Actions.Action memory) {
        return abi.decode(get(list, index), (Actions.Action));
    }

    function toActionArray(DynamicArray memory list) internal pure returns (Actions.Action[] memory) {
        Actions.Action[] memory result = new Actions.Action[](list.length);
        for (uint256 i = 0; i < list.length; ++i) {
            result[i] = abi.decode(list.bytesArray[i], (Actions.Action));
        }
        return result;
    }

    function indexOf(DynamicArray memory list, Actions.Action memory action) internal pure returns (int256) {
        return indexOf(list, abi.encode(action));
    }

    function contains(DynamicArray memory list, Actions.Action memory action) internal pure returns (bool) {
        return contains(list, abi.encode(action));
    }

    // === uint256 ===

    function addUint256(DynamicArray memory list, uint256 item) internal pure returns (DynamicArray memory) {
        return addItem(list, abi.encode(item));
    }

    function getUint256(DynamicArray memory list, uint256 index) internal pure returns (uint256) {
        return abi.decode(get(list, index), (uint256));
    }

    function toUint256Array(DynamicArray memory list) internal pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](list.length);
        for (uint256 i = 0; i < list.length; ++i) {
            result[i] = abi.decode(list.bytesArray[i], (uint256));
        }
        return result;
    }

    function indexOf(DynamicArray memory list, uint256 item) internal pure returns (int256) {
        return indexOf(list, abi.encode(item));
    }

    function contains(DynamicArray memory list, uint256 item) internal pure returns (bool) {
        return contains(list, abi.encode(item));
    }

    // === String ===

    function addString(DynamicArray memory list, string memory item) internal pure returns (DynamicArray memory) {
        return addItem(list, abi.encode(item));
    }

    function getString(DynamicArray memory list, uint256 index) internal pure returns (string memory) {
        return abi.decode(get(list, index), (string));
    }

    function toStringArray(DynamicArray memory list) internal pure returns (string[] memory) {
        string[] memory result = new string[](list.length);
        for (uint256 i = 0; i < list.length; ++i) {
            result[i] = abi.decode(list.bytesArray[i], (string));
        }
        return result;
    }

    function indexOf(DynamicArray memory list, string memory item) internal pure returns (int256) {
        return indexOf(list, abi.encode(item));
    }

    function contains(DynamicArray memory list, string memory item) internal pure returns (bool) {
        return contains(list, abi.encode(item));
    }
}
