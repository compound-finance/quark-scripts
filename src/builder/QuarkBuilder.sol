// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";

import {Actions} from "./Actions.sol";
import {Accounts} from "./Accounts.sol";
import {BridgeRoutes} from "./BridgeRoutes.sol";
import {EIP712Helper} from "./EIP712Helper.sol";
import {Strings} from "./Strings.sol";
import {PaycallWrapper} from "./PaycallWrapper.sol";
import {QuotecallWrapper} from "./QuotecallWrapper.sol";
import {PaymentInfo} from "./PaymentInfo.sol";
import {TokenWrapper} from "./TokenWrapper.sol";

contract QuarkBuilder {
    /* ===== Constants ===== */

    string constant VERSION = "1.0.0";

    /* ===== Custom Errors ===== */

    error AssetPositionNotFound();
    error FundsUnavailable(string assetSymbol, uint256 requiredAmount, uint256 actualAmount);
    error InvalidActionChain();
    error InvalidActionType();
    error InvalidInput();
    error MaxCostTooHigh();

    /* ===== Input Types ===== */

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

    /* ===== Helper Functions ===== */

    /* ===== Main Implementation ===== */

    struct CometSupplyIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        uint256 chainId;
        address comet;
        address sender;
    }

    // TODO: handle supply max
    function cometSupply(
        CometSupplyIntent memory cometSupplyIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory /* builderResult */ ) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        assertFundsAvailable(
            cometSupplyIntent.chainId,
            cometSupplyIntent.assetSymbol,
            cometSupplyIntent.amount,
            chainAccountsList,
            payment
        );

        uint256 actionIndex = 0;
        Actions.Action[] memory actions = new Actions.Action[](chainAccountsList.length);
        IQuarkWallet.QuarkOperation[] memory quarkOperations =
            new IQuarkWallet.QuarkOperation[](chainAccountsList.length);

        if (
            needsBridgedFunds(
                cometSupplyIntent.assetSymbol,
                cometSupplyIntent.amount,
                cometSupplyIntent.chainId,
                chainAccountsList,
                payment
            )
        ) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = cometSupplyIntent.amount;
            // If action is paid for with tokens and the payment token is the transfer token, we need to add the max cost to the amountLeftToBridge for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, cometSupplyIntent.assetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, cometSupplyIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: cometSupplyIntent.assetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: cometSupplyIntent.chainId,
                    recipient: cometSupplyIntent.sender,
                    blockTimestamp: cometSupplyIntent.blockTimestamp,
                    useQuotecall: false // TODO: pass in an actual value for useQuoteCall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                quarkOperations[actionIndex] = bridgeQuarkOperations[i];
                actions[actionIndex] = bridgeActions[i];
                actionIndex++;
            }
        }

        (quarkOperations[actionIndex], actions[actionIndex]) = Actions.cometSupplyAsset(
            Actions.CometSupply({
                chainAccountsList: chainAccountsList,
                assetSymbol: cometSupplyIntent.assetSymbol,
                amount: cometSupplyIntent.amount,
                chainId: cometSupplyIntent.chainId,
                comet: cometSupplyIntent.comet,
                sender: cometSupplyIntent.sender,
                blockTimestamp: cometSupplyIntent.blockTimestamp
            }),
            payment
        );

        // TODO: Bridge payment token

        actionIndex++;

        // Truncate actions and quark operations
        actions = Actions.truncate(actions, actionIndex);
        quarkOperations = Actions.truncate(quarkOperations, actionIndex);

        // Validate generated actions for affordability
        if (payment.isToken) {
            assertSufficientPaymentTokenBalances(actions, chainAccountsList, cometSupplyIntent.chainId);
        }

        // Construct EIP712 digests
        EIP712Helper.EIP712Data memory eip712Data;
        if (quarkOperations.length == 1) {
            eip712Data = EIP712Helper.EIP712Data({
                digest: EIP712Helper.getDigestForQuarkOperation(
                    quarkOperations[0], actions[0].quarkAccount, actions[0].chainId
                    ),
                domainSeparator: EIP712Helper.getDomainSeparator(actions[0].quarkAccount, actions[0].chainId),
                hashStruct: EIP712Helper.getHashStructForQuarkOperation(quarkOperations[0])
            });
        } else if (quarkOperations.length > 1) {
            eip712Data = EIP712Helper.EIP712Data({
                digest: EIP712Helper.getDigestForMultiQuarkOperation(quarkOperations, actions),
                domainSeparator: EIP712Helper.MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR,
                hashStruct: EIP712Helper.getHashStructForMultiQuarkOperation(quarkOperations, actions)
            });
        }

        return BuilderResult({
            version: VERSION,
            actions: actions,
            quarkOperations: quarkOperations,
            paymentCurrency: payment.currency,
            eip712Data: eip712Data
        });
    }

    struct TransferIntent {
        uint256 chainId;
        string assetSymbol;
        uint256 amount;
        address sender;
        address recipient;
        uint256 blockTimestamp;
    }

    function transfer(
        TransferIntent memory transferIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        // Initialize TransferMax flag
        bool isMaxTransfer = transferIntent.amount == type(uint256).max;
        // Convert transferIntent to user aggregated balance
        if (isMaxTransfer) {
            transferIntent.amount = Accounts.totalAvailableAsset(transferIntent.assetSymbol, chainAccountsList, payment);
        }

        assertFundsAvailable(
            transferIntent.chainId, transferIntent.assetSymbol, transferIntent.amount, chainAccountsList, payment
        );

        /*
         * at most two bridge operation per non-destination chain (transfer and payment tokens),
         * and at most one transferIntent operation on the destination chain.
         *
         * therefore the upper bound is 2 * chainAccountsList.length.
         */
        uint256 actionIndex = 0;

        // TransferMax will always use quotecall to avoid leaving dust in wallet
        bool useQuotecall = isMaxTransfer;
        Actions.Action[] memory actions = new Actions.Action[](chainAccountsList.length * 2);
        IQuarkWallet.QuarkOperation[] memory quarkOperations =
            new IQuarkWallet.QuarkOperation[](2 * chainAccountsList.length);

        if (
            needsBridgedFunds(
                transferIntent.assetSymbol, transferIntent.amount, transferIntent.chainId, chainAccountsList, payment
            )
        ) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = transferIntent.amount;
            // If action is paid for with tokens and the payment token is the transfer token, we need to add the max cost to the amountLeftToBridge for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, transferIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: transferIntent.assetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: transferIntent.chainId,
                    recipient: transferIntent.sender,
                    blockTimestamp: transferIntent.blockTimestamp,
                    useQuotecall: useQuotecall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                quarkOperations[actionIndex] = bridgeQuarkOperations[i];
                actions[actionIndex] = bridgeActions[i];
                actionIndex++;
            }
        }

        // If action is paid for with tokens and the payment token is not the transfer token, attempt to bridge some over if not enough
        // Note: The previous code block for bridging the transfer token already handles the case where payment token == transfer token
        if (payment.isToken && !Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)) {
            // Bridge over payment token if not enough
            uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, transferIntent.chainId);
            if (
                needsBridgedFunds(
                    payment.currency, maxCostOnDstChain, transferIntent.chainId, chainAccountsList, payment
                )
            ) {
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: payment.currency,
                        amountNeededOnDst: maxCostOnDstChain,
                        dstChainId: transferIntent.chainId,
                        recipient: transferIntent.sender,
                        blockTimestamp: transferIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                    quarkOperations[actionIndex] = bridgeQuarkOperations[i];
                    actions[actionIndex] = bridgeActions[i];
                    actionIndex++;
                }
            }
        }

        // Check if need to wrap/unwrap token to cover the transferIntent amount
        // If the existing balance is not enough to cover the transferIntent amount, wrap/unwrap the counterpart token here
        // NOTE: We prioritize unwrap/wrap in the dst chain over bridging, bridging logic checks for counterpart tokens when calculating the amounts to bridge.
        uint256 existingBalance =
            Accounts.getBalanceOnChain(transferIntent.assetSymbol, transferIntent.chainId, chainAccountsList);
        if (
            existingBalance < transferIntent.amount
                && TokenWrapper.hasWrapperContract(transferIntent.chainId, transferIntent.assetSymbol)
        ) {
            // If the asset has a wrapper counterpart, wrap/unwrap the token to cover the transferIntent amount
            string memory counterpartSymbol =
                TokenWrapper.getWrapperCounterpartSymbol(transferIntent.chainId, transferIntent.assetSymbol);

            // Wrap/unwrap the token to cover the transferIntent amount
            if (TokenWrapper.isWrappedToken(transferIntent.chainId, transferIntent.assetSymbol)) {
                (quarkOperations[actionIndex], actions[actionIndex]) = Actions.wrapAsset(
                    Actions.WrapAsset({
                        chainAccountsList: chainAccountsList,
                        assetSymbol: counterpartSymbol,
                        // NOTE: Wrap/unwrap the amount needed to cover the transferIntent amount
                        amount: transferIntent.amount - existingBalance,
                        chainId: transferIntent.chainId,
                        sender: transferIntent.sender,
                        blockTimestamp: transferIntent.blockTimestamp
                    }),
                    payment,
                    useQuotecall
                );
                actionIndex++;
            } else {
                (quarkOperations[actionIndex], actions[actionIndex]) = Actions.unwrapAsset(
                    Actions.UnwrapAsset({
                        chainAccountsList: chainAccountsList,
                        assetSymbol: counterpartSymbol,
                        // NOTE: Wrap/unwrap the amount needed to cover the transferIntent amount
                        amount: transferIntent.amount - existingBalance,
                        chainId: transferIntent.chainId,
                        sender: transferIntent.sender,
                        blockTimestamp: transferIntent.blockTimestamp
                    }),
                    payment,
                    useQuotecall
                );
                actionIndex++;
            }
        }

        // Then, transferIntent `amount` of `assetSymbol` to `recipient`
        (quarkOperations[actionIndex], actions[actionIndex]) = Actions.transferAsset(
            Actions.TransferAsset({
                chainAccountsList: chainAccountsList,
                assetSymbol: transferIntent.assetSymbol,
                amount: transferIntent.amount,
                chainId: transferIntent.chainId,
                sender: transferIntent.sender,
                recipient: transferIntent.recipient,
                blockTimestamp: transferIntent.blockTimestamp
            }),
            payment,
            useQuotecall
        );
        actionIndex++;

        // TODO: Merge transactions on same chain into Multicall. Maybe do that separately at the end via a helper function.

        // Truncate actions and quark operations
        actions = Actions.truncate(actions, actionIndex);
        quarkOperations = Actions.truncate(quarkOperations, actionIndex);

        // Validate generated actions for affordability
        if (payment.isToken) {
            assertSufficientPaymentTokenBalances(actions, chainAccountsList, transferIntent.chainId);
        }

        // Construct EIP712 digests
        EIP712Helper.EIP712Data memory eip712Data;
        if (quarkOperations.length == 1) {
            eip712Data = EIP712Helper.EIP712Data({
                digest: EIP712Helper.getDigestForQuarkOperation(
                    quarkOperations[0], actions[0].quarkAccount, actions[0].chainId
                    ),
                domainSeparator: EIP712Helper.getDomainSeparator(actions[0].quarkAccount, actions[0].chainId),
                hashStruct: EIP712Helper.getHashStructForQuarkOperation(quarkOperations[0])
            });
        } else if (quarkOperations.length > 1) {
            eip712Data = EIP712Helper.EIP712Data({
                digest: EIP712Helper.getDigestForMultiQuarkOperation(quarkOperations, actions),
                domainSeparator: EIP712Helper.MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR,
                hashStruct: EIP712Helper.getHashStructForMultiQuarkOperation(quarkOperations, actions)
            });
        }

        return BuilderResult({
            version: VERSION,
            actions: actions,
            quarkOperations: quarkOperations,
            paymentCurrency: payment.currency,
            eip712Data: eip712Data
        });
    }

    // For some reason, funds that may otherwise be bridgeable or held by the user cannot
    // be made available to fulfill the transaction.
    // Funds cannot be bridged, e.g. no bridge exists
    // Funds cannot be withdrawn from Comet, e.g. no reserves
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

                // If the asset has wrapper counterpart and can locally wrap/unwrap, accumulate the balance of the the counterpart
                if (TokenWrapper.hasWrapperContract(chainAccountsList[i].chainId, assetSymbol)) {
                    uint256 counterpartBalance =
                        getWrapperCounterpartBalance(assetSymbol, chainAccountsList[i].chainId, chainAccountsList);
                    // If the user opts for paying with payment token and the payment token is also the action token's counterpart
                    // reduce the available balance by the max cost
                    if (
                        payment.isToken
                            && Strings.stringEqIgnoreCase(
                                payment.currency,
                                TokenWrapper.getWrapperCounterpartSymbol(chainAccountsList[i].chainId, assetSymbol)
                            )
                    ) {
                        uint256 maxCost = PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId);
                        if (counterpartBalance >= maxCost) {
                            counterpartBalance -= maxCost;
                        } else {
                            counterpartBalance = 0;
                        }
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

        return 0;
    }

    function needsBridgedFunds(
        string memory assetSymbol,
        uint256 amount,
        uint256 chainId,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure returns (bool) {
        uint256 balanceOnChain = Accounts.getBalanceOnChain(assetSymbol, chainId, chainAccountsList);
        // If action is paid for with tokens and the payment token is the transfer token, then add the payment max cost for the target chain to the amount needed
        uint256 amountNeededOnDstChain = amount;
        if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, assetSymbol)) {
            amountNeededOnDstChain += PaymentInfo.findMaxCost(payment, chainId);
        }

        // If there exists a counterpart token, try to wrap/unwrap first before attempting to bridge
        uint256 wrapperCounterpartBalance = getWrapperCounterpartBalance(assetSymbol, chainId, chainAccountsList);
        // Subtract max cost if the counterpart token is the payment token
        if (
            payment.isToken
                && Strings.stringEqIgnoreCase(
                    payment.currency, TokenWrapper.getWrapperCounterpartSymbol(chainId, assetSymbol)
                )
        ) {
            uint256 maxCost = PaymentInfo.findMaxCost(payment, chainId);
            if (wrapperCounterpartBalance >= maxCost) {
                wrapperCounterpartBalance -= maxCost;
            } else {
                // Can't afford to wrap/unwrap == can't use that balance
                wrapperCounterpartBalance = 0;
            }
        }
        balanceOnChain += wrapperCounterpartBalance;

        return balanceOnChain < amountNeededOnDstChain;
    }

    // Assert that each chain with a bridge action has enough payment token to
    // cover the payment token cost of the bridging action and that the
    // destination chain (once bridging is complete) will have a sufficient
    // amount of the payment token to cover the non-bridged actions
    function assertSufficientPaymentTokenBalances(
        Actions.Action[] memory actions,
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 targetChainId
    ) internal pure {
        Actions.Action[] memory bridgeActions = Actions.findActionsOfType(actions, Actions.ACTION_TYPE_BRIDGE);
        Actions.Action[] memory nonBridgeActions = Actions.findActionsNotOfType(actions, Actions.ACTION_TYPE_BRIDGE);

        string memory paymentTokenSymbol = nonBridgeActions[0].paymentTokenSymbol; // assumes all actions use the same payment token
        uint256 paymentTokenBridgeAmount = 0;
        // Verify bridge actions are affordable, and update plannedBridgeAmount for verifying transfer actions
        for (uint256 i = 0; i < bridgeActions.length; ++i) {
            Actions.BridgeActionContext memory bridgeActionContext =
                abi.decode(bridgeActions[i].actionContext, (Actions.BridgeActionContext));
            uint256 paymentAssetBalanceOnChain = Accounts.sumBalances(
                Accounts.findAssetPositions(bridgeActions[i].paymentToken, bridgeActions[i].chainId, chainAccountsList)
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

        uint256 targetChainPaymentTokenBalance =
            Accounts.sumBalances(Accounts.findAssetPositions(paymentTokenSymbol, targetChainId, chainAccountsList)); // assumes that all non-bridge actions occur on the target chain
        uint256 paymentTokenCost = 0;

        for (uint256 i = 0; i < nonBridgeActions.length; ++i) {
            Actions.Action memory nonBridgeAction = nonBridgeActions[i];
            if (nonBridgeAction.chainId != targetChainId) {
                revert InvalidActionChain();
            }
            paymentTokenCost += nonBridgeAction.paymentMaxCost;

            if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_TRANSFER)) {
                Actions.TransferActionContext memory transferActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.TransferActionContext));
                if (Strings.stringEqIgnoreCase(transferActionContext.assetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += transferActionContext.amount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_SUPPLY)) {
                Actions.SupplyActionContext memory cometSupplyActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.SupplyActionContext));
                if (Strings.stringEqIgnoreCase(cometSupplyActionContext.assetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += cometSupplyActionContext.amount;
                }
            } else if (
                Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_UNWRAP)
                    || Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_WRAP)
            ) {
                Actions.WrapActionContext memory WrapActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.WrapActionContext));
                if (Strings.stringEqIgnoreCase(WrapActionContext.fromAssetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += WrapActionContext.amount;
                }
            } else {
                revert InvalidActionType();
            }
        }

        if (paymentTokenCost > (targetChainPaymentTokenBalance + paymentTokenBridgeAmount)) {
            revert MaxCostTooHigh();
        }
    }
}
