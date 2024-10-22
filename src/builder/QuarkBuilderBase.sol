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
    /* ===== Output Types ===== */

    struct BuilderResult {
        // Version of the builder interface. (Same as VERSION, but attached to the output.)
        string version;
        // Array of quark operations to execute to fulfill the client intent
        IQuarkWallet.QuarkOperation[] quarkOperations;
        // Array of action context and other metadata corresponding 1:1 with quarkOperations
        Actions.Action[] actions;
        // Struct containing containing EIP-712 data for a QuarkOperation or MultiQuarkOperation
        EIP712Helper.EIP712Data eip712Data;
        // Client-provided paymentCurrency string that was used to derive token addresses.
        // Client may re-use this string to construct a request that simulates the transaction.
        string paymentCurrency;
    }

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

    struct ActionIntent {
        address actor;
        uint256[] amountOuts;
        string[] assetSymbolOuts;
        uint256[] amountIns;
        string[] assetSymbolIns;
        uint256 blockTimestamp;
        uint256 chainId;
    }

    // quark builder base script consists of
    // - tokens that will be used for the actions
    // - bridge tokens if possible
    // - assert account has enough token and pamynet token to complete actions
    // Then insert middle of custom action
    function collectAssetsForAction(
        ActionIntent memory actionIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment,
        IQuarkWallet.QuarkOperation memory quarkOperation,
        Actions.Action memory action,
        bool useQuotecall
    )
        internal
        pure
        returns (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray)
    {
        // Sanity check on ActionIntent
        if (
            actionIntent.amountOuts.length != actionIntent.assetSymbolOuts.length
                || actionIntent.amountIns.length != actionIntent.assetSymbolIns.length
        ) {
            revert InvalidInput();
        }

        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        // Flag to check if the assetSymbolOut(used/supplied/transferred out) is the same as the payment token
        bool paymentTokenInAssetSymbolOut = false;
        {
        for (uint256 i = 0; actionIntent.assetSymbolOuts.length > i; ++i) {
            assertFundsAvailable(
                actionIntent.chainId,
                actionIntent.assetSymbolOuts[i],
                actionIntent.amountOuts[i],
                chainAccountsList,
                payment
            );
            // Check if the assetSymbolOut is the same as the payment token
            if (Strings.stringEqIgnoreCase(actionIntent.assetSymbolOuts[i], payment.currency)) {
                paymentTokenInAssetSymbolOut = true;
            }

            if (
                needsBridgedFunds(
                    actionIntent.assetSymbolOuts[i],
                    actionIntent.amountOuts[i],
                    actionIntent.chainId,
                    chainAccountsList,
                    payment
                )
            ) {
                uint256 amountNeededOnDst = actionIntent.amountOuts[i];
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, actionIntent.assetSymbolOuts[i])) {
                    amountNeededOnDst += PaymentInfo.findMaxCost(payment, actionIntent.chainId);
                }

                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: actionIntent.assetSymbolOuts[i],
                        amountNeededOnDst: amountNeededOnDst,
                        dstChainId: actionIntent.chainId,
                        recipient: actionIntent.actor,
                        blockTimestamp: actionIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 j = 0; j < bridgeQuarkOperations.length; ++j) {
                    List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[j]);
                    List.addAction(actions, bridgeActions[j]);
                }
            }
        }
        }

        {
        if (payment.isToken && !paymentTokenInAssetSymbolOut) {
            uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, actionIntent.chainId);

            for (uint256 k = 0; actionIntent.assetSymbolIns.length > k; ++k) {
                if (Strings.stringEqIgnoreCase(actionIntent.assetSymbolIns[k], payment.currency)) {
                    maxCostOnDstChain = Math.subtractFlooredAtZero(maxCostOnDstChain, actionIntent.amountIns[k]);
                }
            }

            if (
                needsBridgedFunds(payment.currency, maxCostOnDstChain, actionIntent.chainId, chainAccountsList, payment)
            ) {
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: payment.currency,
                        amountNeededOnDst: maxCostOnDstChain,
                        dstChainId: actionIntent.chainId,
                        recipient: actionIntent.actor,
                        blockTimestamp: actionIntent.blockTimestamp,
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
        }

        for (uint256 i = 0; i < actionIntent.assetSymbolOuts.length; ++i) {
            checkAndInsertWrapOrUnwrapAction({
                actions: actions,
                quarkOperations: quarkOperations,
                chainAccountsList: chainAccountsList,
                payment: payment,
                assetSymbol: actionIntent.assetSymbolIns[i],
                amount: actionIntent.amountIns[i],
                chainId: actionIntent.chainId,
                account: actionIntent.actor,
                blockTimestamp: actionIntent.blockTimestamp,
                useQuotecall: useQuotecall
            });
        }

        // Insert action and operation that will be wrapped with this
        List.addAction(actions, action);
        List.addQuarkOperation(quarkOperations, quarkOperation);

        // Convert to array
        quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);
        actionsArray = List.toActionArray(actions);

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

    /* ===== Helper functions ===== */

    function cometRepayMaxAmount(
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 chainId,
        address comet,
        address repayer
    ) internal pure returns (uint256) {
        uint256 totalBorrowForAccount = Accounts.totalBorrowForAccount(chainAccountsList, chainId, comet, repayer);
        uint256 buffer = totalBorrowForAccount / 1000; // 0.1%
        return totalBorrowForAccount + buffer;
    }

    function morphoRepayMaxAmount(
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 chainId,
        address loanToken,
        address collateralToken,
        address repayer
    ) internal pure returns (uint256) {
        uint256 totalBorrowForAccount =
            Accounts.totalMorphoBorrowForAccount(chainAccountsList, chainId, loanToken, collateralToken, repayer);
        uint256 buffer = totalBorrowForAccount / 1000; // 0.1%
        return totalBorrowForAccount + buffer;
    }

    function assertFundsAvailable(
        uint256 chainId,
        string memory assetSymbol,
        uint256 amount,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure {
        // If no funds need to be bridged, then this check is satisfied
        // TODO: We might still need to check the availability of funds on the target chain, e.g. see if
        // funds are locked in a lending protocol and can't be withdrawn
        if (!needsBridgedFunds(assetSymbol, amount, chainId, chainAccountsList, payment)) {
            return;
        }

        // Check each chain to see if there are enough action assets to be bridged over
        uint256 aggregateAssetBalance;
        uint256 aggregateMaxCosts;
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            Accounts.AssetPositions memory positions =
                Accounts.findAssetPositions(assetSymbol, chainAccountsList[i].assetPositionsList);
            if (
                chainAccountsList[i].chainId == chainId
                    || BridgeRoutes.canBridge(chainAccountsList[i].chainId, chainId, assetSymbol)
            ) {
                aggregateAssetBalance += Accounts.sumBalances(positions);
                // If the user opts for paying with the payment token and the payment token is the transfer token, reduce
                // the available balance by the max cost because the max cost is reserved for paying the txn
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, assetSymbol)) {
                    aggregateMaxCosts += PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId);
                }
            }

            // If the asset has wrapper counterpart and can locally wrap/unwrap, accumulate the balance of the the counterpart
            // NOTE: Currently only at dst chain, and will ignore all the counterpart balance in other chains
            if (
                chainAccountsList[i].chainId == chainId
                    && TokenWrapper.hasWrapperContract(chainAccountsList[i].chainId, assetSymbol)
            ) {
                {
                uint256 counterpartBalance =
                    getWrapperCounterpartBalance(assetSymbol, chainAccountsList[i].chainId, chainAccountsList);
                string memory counterpartSymbol =
                    TokenWrapper.getWrapperCounterpartSymbol(chainAccountsList[i].chainId, assetSymbol);
                // If the user opts for paying with payment token and the payment token is also the action token's counterpart
                // reduce the available balance by the max cost
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, counterpartSymbol)) {
                    counterpartBalance = Math.subtractFlooredAtZero(
                        counterpartBalance, PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId)
                    );
                }
                aggregateAssetBalance += counterpartBalance;
                }
            }
        }

        uint256 aggregateAvailableAssetBalance =
            aggregateAssetBalance >= aggregateMaxCosts ? aggregateAssetBalance - aggregateMaxCosts : 0;
        if (aggregateAvailableAssetBalance < amount) {
            revert FundsUnavailable(assetSymbol, amount, aggregateAvailableAssetBalance);
        }
    }

    function needsBridgedFunds(
        string memory assetSymbol,
        uint256 amount,
        uint256 chainId,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure returns (bool) {
        uint256 balanceOnChain = getBalanceOnChain(assetSymbol, chainId, chainAccountsList, payment);
        uint256 amountNeededOnChain = getAmountNeededOnChain(assetSymbol, amount, chainId, payment);

        return balanceOnChain < amountNeededOnChain;
    }

    /**
     * @dev If there is not enough of the asset to cover the amount and the asset has a counterpart asset,
     * insert a wrap/unwrap action to cover the gap in amount.
     */
    function checkAndInsertWrapOrUnwrapAction(
        List.DynamicArray memory actions,
        List.DynamicArray memory quarkOperations,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment,
        string memory assetSymbol,
        uint256 amount,
        uint256 chainId,
        address account,
        uint256 blockTimestamp,
        bool useQuotecall
    ) internal pure {
        // Check if inserting wrapOrUnwrap action is necessary
        uint256 assetBalanceOnChain = Accounts.getBalanceOnChain(assetSymbol, chainId, chainAccountsList);
        if (assetBalanceOnChain < amount && TokenWrapper.hasWrapperContract(chainId, assetSymbol)) {
            // If the asset has a wrapper counterpart, wrap/unwrap the token to cover the transferIntent amount
            string memory counterpartSymbol = TokenWrapper.getWrapperCounterpartSymbol(chainId, assetSymbol);

            // Wrap/unwrap the token to cover the amount
            (IQuarkWallet.QuarkOperation memory wrapOrUnwrapOperation, Actions.Action memory wrapOrUnwrapAction) =
            Actions.wrapOrUnwrapAsset(
                Actions.WrapOrUnwrapAsset({
                    chainAccountsList: chainAccountsList,
                    assetSymbol: counterpartSymbol,
                    // NOTE: Wrap/unwrap the amount needed to cover the amount
                    amount: amount - assetBalanceOnChain,
                    chainId: chainId,
                    sender: account,
                    blockTimestamp: blockTimestamp
                }),
                payment,
                useQuotecall
            );
            List.addQuarkOperation(quarkOperations, wrapOrUnwrapOperation);
            List.addAction(actions, wrapOrUnwrapAction);
        }
    }

    struct PaymentBalanceAssertionArgs {
        Actions.Action[] actions;
        Accounts.ChainAccounts[] chainAccountsList;
        uint256 targetChainId;
        address account;
        uint256 supplementalPaymentTokenBalance;
    }

    /**
     * @dev Asserts that each chain with a bridge action has enough payment
     * token to cover the payment token cost of the bridging action and that
     * the destination chain (once bridging is complete) will have a sufficient
     * amount of the payment token to cover the non-bridged actions.
     *
     * Optional `supplementalPaymentTokenBalance` param describes an amount of
     * the payment token that might have been received in the course of an
     * action (for example, withdrawing an asset from Compound), which would
     * therefore not be present in `chainAccountsList` but could be used to
     * cover action costs.
     */
    function assertSufficientPaymentTokenBalances(
        Actions.Action[] memory actions,
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 targetChainId,
        address account
    ) internal pure {
        return assertSufficientPaymentTokenBalances(
            PaymentBalanceAssertionArgs({
                actions: actions,
                chainAccountsList: chainAccountsList,
                targetChainId: targetChainId,
                account: account,
                supplementalPaymentTokenBalance: 0
            })
        );
    }

    function assertSufficientPaymentTokenBalances(PaymentBalanceAssertionArgs memory args) internal pure {
        Actions.Action[] memory bridgeActions = Actions.findActionsOfType(args.actions, Actions.ACTION_TYPE_BRIDGE);
        Actions.Action[] memory nonBridgeActions =
            Actions.findActionsNotOfType(args.actions, Actions.ACTION_TYPE_BRIDGE);

        string memory paymentTokenSymbol = nonBridgeActions[0].paymentTokenSymbol; // assumes all actions use the same payment token
        uint256 paymentTokenBridgeAmount = 0;
        // Verify bridge actions are affordable, and update plannedBridgeAmount for verifying transfer actions
        for (uint256 i = 0; i < bridgeActions.length; ++i) {
            Actions.BridgeActionContext memory bridgeActionContext =
                abi.decode(bridgeActions[i].actionContext, (Actions.BridgeActionContext));
            uint256 paymentAssetBalanceOnChain = Accounts.sumBalances(
                Accounts.findAssetPositions(
                    bridgeActions[i].paymentToken, bridgeActions[i].chainId, args.chainAccountsList
                )
            );
            if (bridgeActionContext.token == bridgeActions[i].paymentToken) {
                // If the payment token is the transfer token and this is the target chain, we need to account for the transfer amount
                // If its bridge step, check if user has enough balance to cover the bridge amount
                if (paymentAssetBalanceOnChain < bridgeActions[i].paymentMaxCost + bridgeActionContext.amount) {
                    revert MaxCostTooHigh();
                }
            } else {
                // Just check payment token can cover the max cost
                if (paymentAssetBalanceOnChain < bridgeActions[i].paymentMaxCost) {
                    revert MaxCostTooHigh();
                }
            }

            if (Strings.stringEqIgnoreCase(bridgeActionContext.assetSymbol, paymentTokenSymbol)) {
                paymentTokenBridgeAmount += bridgeActionContext.amount;
            }
        }

        uint256 targetChainPaymentTokenBalance = Accounts.sumBalances(
            Accounts.findAssetPositions(paymentTokenSymbol, args.targetChainId, args.chainAccountsList)
        ); // assumes that all non-bridge actions occur on the target chain
        uint256 paymentTokenCost = 0;

        for (uint256 i = 0; i < nonBridgeActions.length; ++i) {
            Actions.Action memory nonBridgeAction = nonBridgeActions[i];
            if (nonBridgeAction.chainId != args.targetChainId) {
                revert InvalidActionChain();
            }
            paymentTokenCost += nonBridgeAction.paymentMaxCost;

            if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_BORROW)) {
                continue;
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_MORPHO_BORROW)) {
                continue;
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_MORPHO_CLAIM_REWARDS))
            {
                continue;
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_MORPHO_REPAY)) {
                Actions.MorphoRepayActionContext memory morphoRepayActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.MorphoRepayActionContext));
                if (morphoRepayActionContext.amount == type(uint256).max) {
                    paymentTokenCost += morphoRepayMaxAmount(
                        args.chainAccountsList,
                        morphoRepayActionContext.chainId,
                        morphoRepayActionContext.token,
                        morphoRepayActionContext.collateralToken,
                        args.account
                    );
                } else {
                    paymentTokenCost += morphoRepayActionContext.amount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_REPAY)) {
                Actions.RepayActionContext memory cometRepayActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.RepayActionContext));
                if (Strings.stringEqIgnoreCase(cometRepayActionContext.assetSymbol, paymentTokenSymbol)) {
                    if (cometRepayActionContext.amount == type(uint256).max) {
                        paymentTokenCost += cometRepayMaxAmount(
                            args.chainAccountsList,
                            cometRepayActionContext.chainId,
                            cometRepayActionContext.comet,
                            args.account
                        );
                    } else {
                        paymentTokenCost += cometRepayActionContext.amount;
                    }
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_SUPPLY)) {
                Actions.SupplyActionContext memory cometSupplyActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.SupplyActionContext));
                if (Strings.stringEqIgnoreCase(cometSupplyActionContext.assetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += cometSupplyActionContext.amount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_MORPHO_VAULT_SUPPLY))
            {
                Actions.MorphoVaultSupplyActionContext memory morphoVaultSupplyActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.MorphoVaultSupplyActionContext));
                if (Strings.stringEqIgnoreCase(morphoVaultSupplyActionContext.assetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += morphoVaultSupplyActionContext.amount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_SWAP)) {
                Actions.SwapActionContext memory swapActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.SwapActionContext));
                if (Strings.stringEqIgnoreCase(swapActionContext.inputAssetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += swapActionContext.inputAmount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_RECURRING_SWAP)) {
                Actions.RecurringSwapActionContext memory recurringSwapActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.RecurringSwapActionContext));
                if (Strings.stringEqIgnoreCase(recurringSwapActionContext.inputAssetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += recurringSwapActionContext.inputAmount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_TRANSFER)) {
                Actions.TransferActionContext memory transferActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.TransferActionContext));
                if (Strings.stringEqIgnoreCase(transferActionContext.assetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += transferActionContext.amount;
                }
            } else if (
                Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_UNWRAP)
                    || Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_WRAP)
            ) {
                // XXX test that wrapping/unwrapping impacts paymentTokenCost
                Actions.WrapOrUnwrapActionContext memory wrapOrUnwrapActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.WrapOrUnwrapActionContext));
                if (Strings.stringEqIgnoreCase(wrapOrUnwrapActionContext.fromAssetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += wrapOrUnwrapActionContext.amount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_WITHDRAW)) {
                continue;
            } else if (
                Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_MORPHO_VAULT_WITHDRAW)
            ) {
                continue;
            } else {
                revert InvalidActionType();
            }
        }

        if (
            paymentTokenCost
                > (targetChainPaymentTokenBalance + paymentTokenBridgeAmount + args.supplementalPaymentTokenBalance)
        ) {
            revert MaxCostTooHigh();
        }
    }

    function getWrapperCounterpartBalance(
        string memory assetSymbol,
        uint256 chainId,
        Accounts.ChainAccounts[] memory chainAccountsList
    ) internal pure returns (uint256) {
        if (TokenWrapper.hasWrapperContract(chainId, assetSymbol)) {
            // Add counterpart balance to balanceOnChain
            return Accounts.getBalanceOnChain(
                TokenWrapper.getWrapperCounterpartSymbol(chainId, assetSymbol), chainId, chainAccountsList
            );
        }

        revert MissingWrapperCounterpart();
    }

    function getBalanceOnChain(
        string memory assetSymbol,
        uint256 chainId,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure returns (uint256) {
        uint256 balanceOnChain = Accounts.getBalanceOnChain(assetSymbol, chainId, chainAccountsList);

        // If there exists a counterpart token, try to wrap/unwrap first before attempting to bridge
        if (TokenWrapper.hasWrapperContract(chainId, assetSymbol)) {
            uint256 counterpartBalance = getWrapperCounterpartBalance(assetSymbol, chainId, chainAccountsList);
            // Subtract max cost if the counterpart token is the payment token
            if (
                payment.isToken
                    && Strings.stringEqIgnoreCase(
                        payment.currency, TokenWrapper.getWrapperCounterpartSymbol(chainId, assetSymbol)
                    )
            ) {
                // 0 if account can't afford to wrap/unwrap == can't use that balance
                counterpartBalance =
                    Math.subtractFlooredAtZero(counterpartBalance, PaymentInfo.findMaxCost(payment, chainId));
            }
            balanceOnChain += counterpartBalance;
        }

        return balanceOnChain;
    }

    function getAmountNeededOnChain(
        string memory assetSymbol,
        uint256 amount,
        uint256 chainId,
        PaymentInfo.Payment memory payment
    ) internal pure returns (uint256) {
        // If action is paid for with tokens and the payment token is the transfer token, then add the payment max cost for the target chain to the amount needed
        uint256 amountNeededOnChain = amount;
        if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, assetSymbol)) {
            amountNeededOnChain += PaymentInfo.findMaxCost(payment, chainId);
        }

        return amountNeededOnChain;
    }
}
