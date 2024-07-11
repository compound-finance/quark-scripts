// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

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

    function toArray(
        DynamicArray memory list
    ) internal pure returns (bytes[] memory) {
        bytes[] memory result = new bytes[](list.length);
        for (uint256 i = 0; i < list.length; ++i) {
            result[i] = list.bytesArray[i];
        }
        return result;
    }

    function addItem(
        DynamicArray memory list,
        bytes memory item
    ) internal pure {
        if (list.length >= list.bytesArray.length) {
            bytes[] memory newBytesArray = new bytes[](
                list.bytesArray.length * 2 + 1
            );
            for (uint256 i = 0; i < list.length; ++i) {
                newBytesArray[i] = list.bytesArray[i];
            }
            list.bytesArray = newBytesArray;
        }

        list.bytesArray[list.length] = item;
        list.length++;
    }

    function get(
        DynamicArray memory list,
        uint256 index
    ) internal pure returns (bytes memory) {
        if (index >= list.length) revert IndexOutOfBound();
        return list.bytesArray[index];
    }

    // Struct APIs

    // === QuarkOperations ===

    function addQuarkOperation(
        DynamicArray memory list,
        IQuarkWallet.QuarkOperation memory operation
    ) internal pure {
        addItem(list, abi.encode(operation));
    }

    function getQuarkOperation(
        DynamicArray memory list,
        uint256 index
    ) internal pure returns (IQuarkWallet.QuarkOperation memory) {
        return abi.decode(get(list, index), (IQuarkWallet.QuarkOperation));
    }

    function toQuarkOperationArray(
        DynamicArray memory list
    ) internal pure returns (IQuarkWallet.QuarkOperation[] memory) {
        IQuarkWallet.QuarkOperation[]
            memory result = new IQuarkWallet.QuarkOperation[](list.length);
        for (uint256 i = 0; i < list.length; ++i) {
            result[i] = abi.decode(
                list.bytesArray[i],
                (IQuarkWallet.QuarkOperation)
            );
        }
        return result;
    }

    // === Action ===

    function addAction(
        DynamicArray memory list,
        Actions.Action memory action
    ) internal pure {
        addItem(list, abi.encode(action));
    }

    function getAction(
        DynamicArray memory list,
        uint256 index
    ) internal pure returns (Actions.Action memory) {
        return abi.decode(get(list, index), (Actions.Action));
    }

    function toActionArray(
        DynamicArray memory list
    ) internal pure returns (Actions.Action[] memory) {
        Actions.Action[] memory result = new Actions.Action[](list.length);
        for (uint256 i = 0; i < list.length; ++i) {
            result[i] = abi.decode(list.bytesArray[i], (Actions.Action));
        }
        return result;
    }
}
