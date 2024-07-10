// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {Math} from "src/lib/Math.sol";
import {PaymentInfo} from "./PaymentInfo.sol";
import {Strings} from "./Strings.sol";
import {PaymentInfo} from "./PaymentInfo.sol";
import {TokenWrapper} from "./TokenWrapper.sol";

library Accounts {
    struct ChainAccounts {
        uint256 chainId;
        QuarkState[] quarkStates;
        AssetPositions[] assetPositionsList;
    }

    // We map this to the Portfolio data structure that the client will already have.
    // This includes fields that builder may not necessarily need, however it makes
    // the client encoding that much simpler.
    struct QuarkState {
        address account;
        uint96 quarkNextNonce;
    }

    // Similarly, this is designed to intentionally reduce the encoding burden for the client
    // by making it equivalent in structure to data already in portfolios.
    struct AssetPositions {
        address asset;
        string symbol;
        uint256 decimals;
        uint256 usdPrice;
        AccountBalance[] accountBalances;
    }

    struct AccountBalance {
        address account;
        uint256 balance;
    }

    function findChainAccounts(uint256 chainId, ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (ChainAccounts memory found)
    {
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            if (chainAccountsList[i].chainId == chainId) {
                return found = chainAccountsList[i];
            }
        }
    }

    function findAssetPositions(string memory assetSymbol, AssetPositions[] memory assetPositionsList)
        internal
        pure
        returns (AssetPositions memory found)
    {
        for (uint256 i = 0; i < assetPositionsList.length; ++i) {
            if (Strings.stringEqIgnoreCase(assetSymbol, assetPositionsList[i].symbol)) {
                return found = assetPositionsList[i];
            }
        }
    }

    function findAssetPositions(string memory assetSymbol, uint256 chainId, ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (AssetPositions memory found)
    {
        ChainAccounts memory chainAccounts = findChainAccounts(chainId, chainAccountsList);
        return findAssetPositions(assetSymbol, chainAccounts.assetPositionsList);
    }

    function findAssetPositions(address assetAddress, AssetPositions[] memory assetPositionsList)
        internal
        pure
        returns (AssetPositions memory found)
    {
        for (uint256 i = 0; i < assetPositionsList.length; ++i) {
            if (assetAddress == assetPositionsList[i].asset) {
                return found = assetPositionsList[i];
            }
        }
    }

    function findAssetPositions(address assetAddress, uint256 chainId, ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (AssetPositions memory found)
    {
        ChainAccounts memory chainAccounts = findChainAccounts(chainId, chainAccountsList);
        return findAssetPositions(assetAddress, chainAccounts.assetPositionsList);
    }

    function findQuarkState(address account, Accounts.QuarkState[] memory quarkStates)
        internal
        pure
        returns (Accounts.QuarkState memory state)
    {
        for (uint256 i = 0; i < quarkStates.length; ++i) {
            if (quarkStates[i].account == account) {
                return state = quarkStates[i];
            }
        }
    }

    function findChainAccountsWithPaymentInfo(
        ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure returns (ChainAccounts[] memory found) {
        ChainAccounts[] memory filteredAccounts = new ChainAccounts[](chainAccountsList.length);
        uint256 count = 0;

        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            if (PaymentInfo.hasMaxCostForChain(payment, chainAccountsList[i].chainId)) {
                filteredAccounts[count++] = chainAccountsList[i];
            }
        }

        return truncate(filteredAccounts, count);
    }

    function sumBalances(AssetPositions memory assetPositions) internal pure returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < assetPositions.accountBalances.length; ++i) {
            totalBalance += assetPositions.accountBalances[i].balance;
        }
        return totalBalance;
    }

    function getBalanceOnChain(string memory assetSymbol, uint256 chainId, ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (uint256)
    {
        AssetPositions memory positions = findAssetPositions(assetSymbol, chainId, chainAccountsList);
        return sumBalances(positions);
    }

    /*
    * @notice Get the total available asset balance for a given token symbol across chains
    * Substraction of max cost is done if the payment token is the transfer token to readjust the available balance
    * @param tokenSymbol The token symbol to check
    * @param chainAccountsList The list of chain accounts to check
    * @param payment The payment info to check
    * @return The total available asset balance
    */
    function totalAvailableAsset(
        string memory tokenSymbol,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure returns (uint256) {
        uint256 total = 0;

        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            uint256 balance = Accounts.sumBalances(
                Accounts.findAssetPositions(tokenSymbol, chainAccountsList[i].chainId, chainAccountsList)
            );

            // Account for max cost if the payment token is the transfer token
            // Simply offset the max cost from the available asset batch
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, tokenSymbol)) {
                // Use subtractFlooredAtZero to prevent errors from underflowing
                balance =
                    Math.subtractFlooredAtZero(balance, PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId));
            }

            // If the wrapper contract exists in the chain, add the balance of the wrapped/unwrapped token here as well
            // Offset with another max cost for wrapping/unwrapping action when the counter part is payment token
            uint256 counterpartBalance = 0;
            if (TokenWrapper.hasWrapperContract(chainAccountsList[i].chainId, tokenSymbol)) {
                // Add the balance of the wrapped token
                counterpartBalance += Accounts.sumBalances(
                    Accounts.findAssetPositions(
                        TokenWrapper.getWrapperCounterpartSymbol(chainAccountsList[i].chainId, tokenSymbol),
                        chainAccountsList[i].chainId,
                        chainAccountsList
                    )
                );
                // If the wrapped token is the payment token, offset the max cost
                if (
                    payment.isToken
                        && Strings.stringEqIgnoreCase(
                            payment.currency,
                            TokenWrapper.getWrapperCounterpartSymbol(chainAccountsList[i].chainId, tokenSymbol)
                        )
                ) {
                    counterpartBalance = Math.subtractFlooredAtZero(
                        counterpartBalance, PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId)
                    );
                }
            }

            total += balance + counterpartBalance;
        }
        return total;
    }

    function truncate(ChainAccounts[] memory chainAccountsList, uint256 length)
        internal
        pure
        returns (ChainAccounts[] memory)
    {
        ChainAccounts[] memory result = new ChainAccounts[](length);
        for (uint256 i = 0; i < length; ++i) {
            result[i] = chainAccountsList[i];
        }
        return result;
    }
}
