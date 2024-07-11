// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {CodeJarHelper} from "./CodeJarHelper.sol";
import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Multicall} from "../Multicall.sol";
import {Actions} from "./Actions.sol";

// Helper library to merge QuarkOperations on the same chain
library QuarkOperationHelper {
    function mergeSameChainOperations(
        IQuarkWallet.QuarkOperation[] memory quarkOperations,
        Actions.Action[] memory actions
    ) internal pure returns (IQuarkWallet.QuarkOperation[] memory, Actions.Action[] memory) {
        // Note: Assumes quarkOperations and actions have the same length

        // Arrays to keep track of unique chain IDs and their operations
        uint256[] memory uniqueChainIds = new uint256[](quarkOperations.length);
        uint256[] memory operationCounts = new uint256[](quarkOperations.length);
        uint256 uniqueChainCount = 0;

        // Count operations per chain
        for (uint256 i = 0; i < quarkOperations.length; ++i) {
            uint256 chainId = actions[i].chainId;
            bool found = false;
            for (uint256 j = 0; j < uniqueChainCount; j++) {
                if (uniqueChainIds[j] == chainId) {
                    operationCounts[j]++;
                    found = true;
                    break;
                }
            }
            if (!found) {
                uniqueChainIds[uniqueChainCount] = chainId;
                operationCounts[uniqueChainCount] = 1;
                uniqueChainCount++;
            }
        }

        // 2D array to group operations and actions by chain id
        IQuarkWallet.QuarkOperation[][] memory groupedQuarkOperations =
            new IQuarkWallet.QuarkOperation[][](uniqueChainCount);
        Actions.Action[][] memory groupedActions = new Actions.Action[][](uniqueChainCount);

        // Initialize grouped arrays
        for (uint256 i = 0; i < uniqueChainCount; ++i) {
            groupedQuarkOperations[i] = new IQuarkWallet.QuarkOperation[](operationCounts[i]);
            groupedActions[i] = new Actions.Action[](operationCounts[i]);
        }

        // Group operations by chain
        uint256[] memory currentIndex = new uint256[](uniqueChainCount);
        for (uint256 i = 0; i < quarkOperations.length; ++i) {
            uint256 chainId = actions[i].chainId;
            for (uint256 j = 0; j < uniqueChainCount; j++) {
                if (uniqueChainIds[j] == chainId) {
                    groupedQuarkOperations[j][currentIndex[j]] = quarkOperations[i];
                    groupedActions[j][currentIndex[j]] = actions[i];
                    currentIndex[j]++;
                    break;
                }
            }
        }

        // Create new arrays for merged operations and actions
        IQuarkWallet.QuarkOperation[] memory mergedQuarkOperations = new IQuarkWallet.QuarkOperation[](uniqueChainCount);
        Actions.Action[] memory mergedActions = new Actions.Action[](uniqueChainCount);

        // Merge operations for each unique chain
        for (uint256 i = 0; i < uniqueChainCount; ++i) {
            if (operationCounts[i] == 1) {
                // If there's only one operation for this chain, we don't need to merge
                mergedQuarkOperations[i] = groupedQuarkOperations[i][0];
                mergedActions[i] = groupedActions[i][0];
            } else {
                // Merge multiple operations for this chain
                (mergedQuarkOperations[i], mergedActions[i]) =
                    mergeOperations(groupedQuarkOperations[i], groupedActions[i]);
            }
        }

        return (mergedQuarkOperations, mergedActions);
    }

    // Note: Assumes all the quark operations are for the same quark wallet.
    function mergeOperations(IQuarkWallet.QuarkOperation[] memory quarkOperations, Actions.Action[] memory actions)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Actions.Action memory)
    {
        address[] memory callContracts = new address[](quarkOperations.length);
        bytes[] memory callDatas = new bytes[](quarkOperations.length);
        bytes[] memory scriptSources = new bytes[](quarkOperations.length + 1);

        for (uint256 i = 0; i < quarkOperations.length; ++i) {
            callContracts[i] = quarkOperations[i].scriptAddress;
            callDatas[i] = quarkOperations[i].scriptCalldata;
            // Note: For simplicity, we assume there is one script source per quark operation for now
            scriptSources[i] = quarkOperations[i].scriptSources[0];
        }
        scriptSources[quarkOperations.length] = type(Multicall).creationCode;

        bytes memory multicallCalldata = abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas);

        // Construct QuarkOperation and Action
        // Note: We give precedence to the last operation and action for now because any earlier operations
        // are auxiliary (e.g. wrapping an asset)
        IQuarkWallet.QuarkOperation memory lastQuarkOperation = quarkOperations[quarkOperations.length - 1];
        IQuarkWallet.QuarkOperation memory mergedQuarkOperation = IQuarkWallet.QuarkOperation({
            nonce: lastQuarkOperation.nonce,
            scriptAddress: CodeJarHelper.getCodeAddress(type(Multicall).creationCode),
            scriptCalldata: multicallCalldata,
            scriptSources: scriptSources,
            expiry: lastQuarkOperation.expiry
        });

        return (mergedQuarkOperation, actions[actions.length - 1]);
    }
}
