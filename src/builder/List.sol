// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Actions} from "./Actions.sol";

library List {
    error IndexOutOfBound();

    struct ListStuct {
        bytes[] bytesArray;
        uint256 size;
    }

    function newList() internal pure returns (ListStuct memory) {
        return ListStuct(new bytes[](0), 0);
    }

    function toArray(ListStuct memory list) internal pure returns (bytes[] memory) {
        bytes[] memory result = new bytes[](list.size);
        for (uint256 i = 0; i < list.size; ++i) {
            result[i] = list.bytesArray[i];
        }
        return result;
    }

    function add(ListStuct memory list, bytes memory item) internal pure {
        if ((list.size + 1) * 2 > list.bytesArray.length) {
            bytes[] memory newBytesArray = new bytes[]((list.bytesArray.length + 1) * 2);
            for (uint256 i = 0; i < list.size; ++i) {
                newBytesArray[i] = list.bytesArray[i];
            }
            newBytesArray[list.size] = item;

            list.bytesArray = newBytesArray;
            list.size = list.size + 1;
        } else {
            list.bytesArray[list.size] = item;
            list.size = list.size + 1;
        }
    }

    function get(ListStuct memory list, uint256 index) internal pure returns (bytes memory) {
        if (index >= list.size) revert IndexOutOfBound();
        return list.bytesArray[index];
    }

    // Structs' APIs

    // === QuarkOperations ===
    function addQuarkOperation(ListStuct memory list, IQuarkWallet.QuarkOperation memory operation) internal pure {
        add(list, abi.encode(operation));
    }

    function getQuarkOperation(ListStuct memory list, uint256 index)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory)
    {
        return abi.decode(get(list, index), (IQuarkWallet.QuarkOperation));
    }

    function toQuarkOperationArray(ListStuct memory list)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation[] memory)
    {
        IQuarkWallet.QuarkOperation[] memory result = new IQuarkWallet.QuarkOperation[](list.size);
        for (uint256 i = 0; i < list.size; ++i) {
            result[i] = abi.decode(list.bytesArray[i], (IQuarkWallet.QuarkOperation));
        }
        return result;
    }

    // === Action ===
    function addAction(ListStuct memory list, Actions.Action memory action) internal pure {
        add(list, abi.encode(action));
    }

    function getAction(ListStuct memory list, uint256 index) internal pure returns (Actions.Action memory) {
        return abi.decode(get(list, index), (Actions.Action));
    }

    function toActionArray(ListStuct memory list) internal pure returns (Actions.Action[] memory) {
        Actions.Action[] memory result = new Actions.Action[](list.size);
        for (uint256 i = 0; i < list.size; ++i) {
            result[i] = abi.decode(list.bytesArray[i], (Actions.Action));
        }
        return result;
    }
}
