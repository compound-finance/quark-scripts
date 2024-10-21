// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Actions} from "src/builder/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {EIP712Helper} from "src/builder/EIP712Helper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

contract RecurringSwap is QuarkBuilderBase {
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
    ) external pure returns (BuilderResult memory) {
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
                autoWrapperEnabled: false,
                chainAccountsList: chainAccountsList,
                payment: payment,
                quarkOperation: operation,
                action: action
            });
        }

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
            collectAssetsForAction(actionIntent);

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }
}
