// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";

import {Actions} from "./Actions.sol";
import {Accounts} from "./Accounts.sol";
import {BridgeRoutes} from "./BridgeRoutes.sol";
import {EIP712Helper} from "./EIP712Helper.sol";
import {Math} from "src/lib/Math.sol";
import {MorphoInfo} from "./MorphoInfo.sol";
import {Strings} from "./Strings.sol";
import {PaycallWrapper} from "./PaycallWrapper.sol";
import {QuotecallWrapper} from "./QuotecallWrapper.sol";
import {PaymentInfo} from "./PaymentInfo.sol";
import {TokenWrapper} from "./TokenWrapper.sol";
import {QuarkOperationHelper} from "./QuarkOperationHelper.sol";
import {List} from "./List.sol";

contract QuarkBuilderBase {
    /* ===== Constants ===== */

    string constant VERSION = "0.1.1";

    /* ===== Custom Errors ===== */

    error AssetPositionNotFound();
    error FundsUnavailable(string assetSymbol, uint256 requiredAmount, uint256 actualAmount);
    error InvalidActionChain();
    error InvalidActionType();
    error InvalidInput();
    error MaxCostTooHigh();
    error MissingWrapperCounterpart();
    error InvalidRepayActionContext();


    struct BaseIntent {
        address actor;
        uint256 amount;       
        string assetSymbol; 
        uint256 blockTimestamp;
        uint256 chainId;
    }

    // quark builder base script consists of
    // - token that will b euse for the actions
    // - bridge token if possible
    // - assert account has enough token and pamynet token to complete actions
    // Then insert middle of custom action
    function wrapQuarkBuilderBaseScripts(
        BaseIntent memory baseIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment,
        IQuarkWallet.QuarkOperation quarkOperation,
        Actions.Action action,
        uint256 supplementalPaymentToken,
        bool useQuotecall
    ) internal pure returns (List.DynamicArray memory quarkOperations,  List.DynamicArray memory actions) {
        assertFundsAvailable(baseIntent.chainId, baseIntent.assetSymbol, baseIntent.amount, chainAccountsList, payment);
        actions = List.newList();
        quarkOperations = List.newList();

        if (needsBridgedFunds(baseIntent.assetSymbol, baseIntent.amount, baseIntent.chainId, chainAccountsList, payment)) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = baseIntent.amount;
            // If action is paid for with tokens and the payment token is the
            // repay token, we need to add the max cost to the
            // amountNeededOnDst for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, baseIntent.assetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, baseIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: baseIntent.assetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: baseIntent.chainId,
                    recipient: baseIntent.actor,
                    blockTimestamp: baseIntent.blockTimestamp,
                    useQuotecall: useQuotecall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                List.addAction(actions, bridgeActions[i]);
                List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
            }
        }

        // Only bridge payment token if it is not the baseIntent asset
        if (payment.isToken && !Strings.stringEqIgnoreCase(baseIntent.assetSymbol, payment.currency)) {
            uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, baseIntent.chainId);
            if (Strings.stringEqIgnoreCase(payment.currency, baseIntent.assetSymbol)) {
                maxCostOnDstChain = Math.subtractFlooredAtZero(maxCostOnDstChain, baseIntent.amount);
            }

            if (needsBridgedFunds(payment.currency, maxCostOnDstChain, baseIntent.chainId, chainAccountsList, payment))
            {
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: payment.currency,
                        amountNeededOnDst: maxCostOnDstChain,
                        dstChainId: baseIntent.chainId,
                        recipient: baseIntent.actor,
                        blockTimestamp: baseIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                    List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
                    List.addAction(actions, bridgeActions[i]);
                }
            }
        }

        // Auto-wrap
        checkAndInsertWrapOrUnwrapAction(
            actions,
            quarkOperations,
            chainAccountsList,
            payment,
            baseIntent.assetSymbol,
            baseIntent.amount,
            baseIntent.chainId,
            baseIntent.actor,
            baseIntent.blockTimestamp,
            useQuotecall
        );

        // Add intented derived actions
        List.addAction(actions, action);
        List.addQuarkOperation(quarkOperations, quarkOperation);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

        // Validate generated actions for affordability
        if (payment.isToken) {
            assertSufficientPaymentTokenBalances(
                PaymentBalanceAssertionArgs({
                    actions: actionsArray,
                    chainAccountsList: chainAccountsList,
                    targetChainId: repayIntent.chainId,
                    account: repayIntent.repayer,
                    supplementalPaymentTokenBalance: supplementalPaymentToken
                })
            );
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
    }
}
