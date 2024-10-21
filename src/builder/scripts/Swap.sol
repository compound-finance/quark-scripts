// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Actions} from "src/builder/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {EIP712Helper} from "src/builder/EIP712Helper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

contract Swap is QuarkBuilderBase {
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
    ) external pure returns (BuilderResult memory) {
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
                    autoWrapperEnabled: true,
                    chainAccountsList: chainAccountsList,
                    payment: payment,
                    quarkOperation: operation,
                    action: action
                });
            }

            (quarkOperationsArray, actionsArray) = collectAssetsForAction(actionIntent);
        }
        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }
}
