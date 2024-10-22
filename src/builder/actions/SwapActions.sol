// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";

import {Actions} from "src/builder/Actions.sol";
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

contract SwapActions is QuarkBuilderBase {
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

        string memory sellAssetSymbol =
            Accounts.findAssetPositions(swapIntent.sellToken, swapIntent.chainId, chainAccountsList).symbol;
        string memory buyAssetSymbol =
            Accounts.findAssetPositions(swapIntent.buyToken, swapIntent.chainId, chainAccountsList).symbol;
        string memory feeAssetSymbol =
            Accounts.findAssetPositions(swapIntent.feeToken, swapIntent.chainId, chainAccountsList).symbol;

        // Initialize swap max flag (when sell amount is max)
        bool isMaxSwap = swapIntent.sellAmount == type(uint256).max;
        // Convert swapIntent to user aggregated balance
        if (isMaxSwap) {
            swapIntent.sellAmount = Accounts.totalAvailableAsset(sellAssetSymbol, chainAccountsList, payment);
        }

        bool useQuotecall = isMaxSwap;

        // Then, swap `amount` of `assetSymbol` to `recipient`
        (IQuarkWallet.QuarkOperation memory operation, Actions.Action memory action) = Actions.zeroExSwap(
            Actions.ZeroExSwap({
                chainAccountsList: chainAccountsList,
                entryPoint: swapIntent.entryPoint,
                swapData: swapIntent.swapData,
                sellToken: swapIntent.sellToken,
                sellAssetSymbol: sellAssetSymbol,
                sellAmount: swapIntent.sellAmount,
                buyToken: swapIntent.buyToken,
                buyAssetSymbol: buyAssetSymbol,
                buyAmount: swapIntent.buyAmount,
                feeToken: swapIntent.feeToken,
                feeAssetSymbol: feeAssetSymbol,
                feeAmount: swapIntent.feeAmount,
                chainId: swapIntent.chainId,
                sender: swapIntent.sender,
                isExactOut: swapIntent.isExactOut,
                blockTimestamp: swapIntent.blockTimestamp
            }),
            payment,
            useQuotecall
        );

        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray;
        Actions.Action[] memory actionsArray;
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = swapIntent.sellAmount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = sellAssetSymbol;
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = swapIntent.buyAmount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = buyAssetSymbol;

            (quarkOperationsArray, actionsArray) = QuarkBuilderBase.collectAssetsForAction({
                actionIntent: QuarkBuilderBase.ActionIntent({
                    actor: swapIntent.sender,
                    amountIns: amountIns,
                    assetSymbolIns: assetSymbolIns,
                    amountOuts: amountOuts,
                    assetSymbolOuts: assetSymbolOuts,
                    blockTimestamp: swapIntent.blockTimestamp,
                    chainId: swapIntent.chainId
                }),
                chainAccountsList: chainAccountsList,
                payment: payment,
                quarkOperation: operation,
                action: action,
                useQuotecall: useQuotecall
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
    ) external pure returns (BuilderResult memory) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        string memory sellAssetSymbol =
            Accounts.findAssetPositions(swapIntent.sellToken, swapIntent.chainId, chainAccountsList).symbol;
        string memory buyAssetSymbol =
            Accounts.findAssetPositions(swapIntent.buyToken, swapIntent.chainId, chainAccountsList).symbol;

        // Check there are enough of the input token on the target chain
        if (needsBridgedFunds(sellAssetSymbol, swapIntent.sellAmount, swapIntent.chainId, chainAccountsList, payment)) {
            uint256 balanceOnChain = getBalanceOnChain(sellAssetSymbol, swapIntent.chainId, chainAccountsList, payment);
            uint256 amountNeededOnChain =
                getAmountNeededOnChain(sellAssetSymbol, swapIntent.sellAmount, swapIntent.chainId, payment);
            uint256 maxCostOnChain = payment.isToken ? PaymentInfo.findMaxCost(payment, swapIntent.chainId) : 0;
            uint256 availableAssetBalance = balanceOnChain >= maxCostOnChain ? balanceOnChain - maxCostOnChain : 0;
            revert FundsUnavailable(sellAssetSymbol, amountNeededOnChain, availableAssetBalance);
        }

        // Check there are enough of the payment token on the target chain
        if (payment.isToken) {
            uint256 maxCostOnChain = PaymentInfo.findMaxCost(payment, swapIntent.chainId);
            if (needsBridgedFunds(payment.currency, maxCostOnChain, swapIntent.chainId, chainAccountsList, payment)) {
                uint256 balanceOnChain =
                    getBalanceOnChain(payment.currency, swapIntent.chainId, chainAccountsList, payment);
                revert FundsUnavailable(payment.currency, maxCostOnChain, balanceOnChain);
            }
        }

        // We don't support max swap for recurring swaps, so quote call is never used
        bool useQuotecall = false;
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        // TODO: Handle wrapping/unwrapping once the new Quark is out. That will allow us to construct a replayable
        // Multicall transaction that contains 1) the wrapping/unwrapping action and 2) the recurring swap. The wrapping
        // action will need to be smart: for exact in, it will check that balance < sellAmount before wrapping. For exact out,
        // it will always wrap all.
        // // Auto-wrap/unwrap
        // checkAndInsertWrapOrUnwrapAction(
        //     actions,
        //     quarkOperations,
        //     chainAccountsList,
        //     payment,
        //     sellAssetSymbol,
        //     // TODO: We will need to set this to type(uint256).max if isExactOut is true
        //     swapIntent.sellAmount,
        //     swapIntent.chainId,
        //     swapIntent.sender,
        //     swapIntent.blockTimestamp,
        //     useQuotecall
        // );

        // Then, set up the recurring swap operation
        (IQuarkWallet.QuarkOperation memory operation, Actions.Action memory action) = Actions.recurringSwap(
            Actions.RecurringSwapParams({
                chainAccountsList: chainAccountsList,
                sellToken: swapIntent.sellToken,
                sellAssetSymbol: sellAssetSymbol,
                sellAmount: swapIntent.sellAmount,
                buyToken: swapIntent.buyToken,
                buyAssetSymbol: buyAssetSymbol,
                buyAmount: swapIntent.buyAmount,
                isExactOut: swapIntent.isExactOut,
                path: swapIntent.path,
                interval: swapIntent.interval,
                chainId: swapIntent.chainId,
                sender: swapIntent.sender,
                blockTimestamp: swapIntent.blockTimestamp
            }),
            payment,
            useQuotecall
        );
        List.addAction(actions, action);
        List.addQuarkOperation(quarkOperations, operation);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);
        // Validate generated actions for affordability
        if (payment.isToken) {
            assertSufficientPaymentTokenBalances(actionsArray, chainAccountsList, swapIntent.chainId, swapIntent.sender);
        }

        // Merge operations that are from the same chain into one Multicall operation
        (quarkOperationsArray, actionsArray) =
            QuarkOperationHelper.mergeSameChainOperations(quarkOperationsArray, actionsArray);

        // Wrap operations around Paycall/Quotecall if payment is with token
        if (payment.isToken) {
            quarkOperationsArray = QuarkOperationHelper.wrapOperationsWithTokenPayment(
                quarkOperationsArray, actionsArray, payment, useQuotecall
            );
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
