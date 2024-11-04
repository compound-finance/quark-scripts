// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Actions} from "src/builder/actions/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {BridgeRoutes} from "src/builder/BridgeRoutes.sol";
import {EIP712Helper} from "src/builder/EIP712Helper.sol";
import {Math} from "src/lib/Math.sol";
import {MorphoInfo} from "src/builder/MorphoInfo.sol";
import {Strings} from "src/builder/Strings.sol";
import {PaycallWrapper} from "src/builder/PaycallWrapper.sol";
import {QuotecallWrapper} from "src/builder/QuotecallWrapper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {TokenWrapper} from "src/builder/TokenWrapper.sol";
import {QuarkOperationHelper} from "src/builder/QuarkOperationHelper.sol";
import {List} from "src/builder/List.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

contract SwapActionsBuilder is QuarkBuilderBase {
    struct ZeroExSwapIntent {
        uint256 chainId;
        address entryPoint;
        bytes swapData;
        address sellToken;
        uint256 sellAmount;
        address buyToken;
        uint256 buyAmount;
        address feeToken;
        uint256 feeAmount;
        address sender;
        bool isExactOut;
        uint256 blockTimestamp;
    }

    function swap(
        ZeroExSwapIntent memory swapIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external view returns (BuilderResult memory) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        IQuarkWallet.QuarkOperation memory operation;
        Actions.Action memory action;
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray;
        Actions.Action[] memory actionsArray;

        {
            // Initialize swap max flag (when sell amount is max)
            bool isMaxSwap = swapIntent.sellAmount == type(uint256).max;
            // Convert swapIntent to user aggregated balance
            if (isMaxSwap) {
                swapIntent.sellAmount = Accounts.totalAvailableAsset(
                    Accounts.findAssetPositions(swapIntent.sellToken, swapIntent.chainId, chainAccountsList).symbol,
                    chainAccountsList,
                    payment
                );
            }

            // Then, swap `amount` of `assetSymbol` to `recipient`
            (operation, action) = Actions.zeroExSwap(
                Actions.ZeroExSwap({
                    chainAccountsList: chainAccountsList,
                    entryPoint: swapIntent.entryPoint,
                    swapData: swapIntent.swapData,
                    sellToken: swapIntent.sellToken,
                    sellAssetSymbol: Accounts.findAssetPositions(
                        swapIntent.sellToken, swapIntent.chainId, chainAccountsList
                        ).symbol,
                    sellAmount: swapIntent.sellAmount,
                    buyToken: swapIntent.buyToken,
                    buyAssetSymbol: Accounts.findAssetPositions(swapIntent.buyToken, swapIntent.chainId, chainAccountsList)
                        .symbol,
                    buyAmount: swapIntent.buyAmount,
                    feeToken: swapIntent.feeToken,
                    feeAssetSymbol: Accounts.findAssetPositions(swapIntent.feeToken, swapIntent.chainId, chainAccountsList)
                        .symbol,
                    feeAmount: swapIntent.feeAmount,
                    chainId: swapIntent.chainId,
                    sender: swapIntent.sender,
                    isExactOut: swapIntent.isExactOut,
                    blockTimestamp: swapIntent.blockTimestamp
                }),
                payment,
                isMaxSwap
            );

            ActionIntent memory actionIntent;
            // Note: Scope to avoid stack too deep errors
            {
                uint256[] memory amountOuts = new uint256[](1);
                amountOuts[0] = swapIntent.sellAmount;
                string[] memory assetSymbolOuts = new string[](1);
                assetSymbolOuts[0] =
                    Accounts.findAssetPositions(swapIntent.sellToken, swapIntent.chainId, chainAccountsList).symbol;
                uint256[] memory amountIns = new uint256[](1);
                amountIns[0] = swapIntent.buyAmount;
                string[] memory assetSymbolIns = new string[](1);
                assetSymbolIns[0] =
                    Accounts.findAssetPositions(swapIntent.buyToken, swapIntent.chainId, chainAccountsList).symbol;
                actionIntent = ActionIntent({
                    actor: swapIntent.sender,
                    amountIns: amountIns,
                    assetSymbolIns: assetSymbolIns,
                    amountOuts: amountOuts,
                    assetSymbolOuts: assetSymbolOuts,
                    blockTimestamp: swapIntent.blockTimestamp,
                    chainId: swapIntent.chainId,
                    useQuotecall: isMaxSwap,
                    bridgeEnabled: true,
                    autoWrapperEnabled: true
                });
            }

            (quarkOperationsArray, actionsArray) = collectAssetsForAction({
                actionIntent: actionIntent,
                chainAccountsList: chainAccountsList,
                payment: payment,
                actionQuarkOperation: operation,
                action: action
            });
        }

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct RecurringSwapIntent {
        uint256 chainId;
        address sellToken;
        // For exact out swaps, this will be an estimate of the expected input token amount for the first swap
        uint256 sellAmount;
        address buyToken;
        uint256 buyAmount;
        bool isExactOut;
        bytes path;
        uint256 interval;
        address sender;
        uint256 blockTimestamp;
    }

    // Note: We don't currently bridge the input token or the payment token for recurring swaps. Recurring swaps
    // are actions tied to assets on a single chain.
    function recurringSwap(
        RecurringSwapIntent memory swapIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external view returns (BuilderResult memory) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        // Then, set up the recurring swap operation
        (IQuarkWallet.QuarkOperation memory operation, Actions.Action memory action) = Actions.recurringSwap(
            Actions.RecurringSwapParams({
                chainAccountsList: chainAccountsList,
                sellToken: swapIntent.sellToken,
                sellAssetSymbol: Accounts.findAssetPositions(swapIntent.sellToken, swapIntent.chainId, chainAccountsList)
                    .symbol,
                sellAmount: swapIntent.sellAmount,
                buyToken: swapIntent.buyToken,
                buyAssetSymbol: Accounts.findAssetPositions(swapIntent.buyToken, swapIntent.chainId, chainAccountsList)
                    .symbol,
                buyAmount: swapIntent.buyAmount,
                isExactOut: swapIntent.isExactOut,
                path: swapIntent.path,
                interval: swapIntent.interval,
                chainId: swapIntent.chainId,
                sender: swapIntent.sender,
                blockTimestamp: swapIntent.blockTimestamp
            }),
            payment,
            false
        );

        ActionIntent memory actionIntent;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = swapIntent.sellAmount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] =
                Accounts.findAssetPositions(swapIntent.sellToken, swapIntent.chainId, chainAccountsList).symbol;
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = swapIntent.buyAmount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] =
                Accounts.findAssetPositions(swapIntent.buyToken, swapIntent.chainId, chainAccountsList).symbol;
            actionIntent = ActionIntent({
                actor: swapIntent.sender,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: swapIntent.blockTimestamp,
                chainId: swapIntent.chainId,
                useQuotecall: false,
                bridgeEnabled: false,
                autoWrapperEnabled: false
            });
        }

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        collectAssetsForAction({
            actionIntent: actionIntent,
            chainAccountsList: chainAccountsList,
            payment: payment,
            actionQuarkOperation: operation,
            action: action
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }
}
