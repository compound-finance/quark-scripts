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

contract QuarkBuilder {
    /* ===== Constants ===== */

    string constant VERSION = "1.0.0";

    /* ===== Custom Errors ===== */

    error AssetPositionNotFound();
    error FundsUnavailable(string assetSymbol, uint256 requiredAmount, uint256 actualAmount, uint256 missingAmount);
    error InsufficientFunds(uint256 requiredAmount, uint256 actualAmount);
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
        assertSufficientFunds(cometSupplyIntent.assetSymbol, cometSupplyIntent.amount, chainAccountsList);
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
                cometSupplyIntent.assetSymbol, cometSupplyIntent.amount, cometSupplyIntent.chainId, chainAccountsList
            )
        ) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 balanceOnDstChain =
                Accounts.getBalanceOnChain(cometSupplyIntent.assetSymbol, cometSupplyIntent.chainId, chainAccountsList);
            uint256 amountLeftToBridge = cometSupplyIntent.amount - balanceOnDstChain;
            // If the payment token is the transfer token and user opt for paying with the payment token, need to add max cost back to the amountLeftToBridge for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, cometSupplyIntent.assetSymbol)) {
                amountLeftToBridge += PaymentInfo.findMaxCost(payment, cometSupplyIntent.chainId);
            }

            uint256 bridgeActionCount = 0;
            // TODO: bridge routing logic (which bridge to prioritize, how many bridges?)
            // Iterate chainAccountList and find up to 2 chains that can provide enough fund
            // Backend can provide optimal routes by adjusting the order in chainAccountList.
            for (uint256 i = 0; i < chainAccountsList.length; ++i) {
                if (amountLeftToBridge == 0) {
                    break;
                }

                Accounts.ChainAccounts memory srcChainAccounts = chainAccountsList[i];
                if (srcChainAccounts.chainId == cometSupplyIntent.chainId) {
                    continue;
                }

                if (
                    !BridgeRoutes.canBridge(
                        srcChainAccounts.chainId, cometSupplyIntent.chainId, cometSupplyIntent.assetSymbol
                    )
                ) {
                    continue;
                }

                Accounts.AssetPositions memory srcAssetPositions =
                    Accounts.findAssetPositions(cometSupplyIntent.assetSymbol, srcChainAccounts.assetPositionsList);
                Accounts.AccountBalance[] memory srcAccountBalances = srcAssetPositions.accountBalances;
                // TODO: Make logic smarter. Currently, this uses a greedy algorithm.
                // e.g. Optimize by trying to bridge with the least amount of bridge operations
                for (uint256 j = 0; j < srcAccountBalances.length; ++j) {
                    uint256 amountToBridge = srcAccountBalances[j].balance >= amountLeftToBridge
                        ? amountLeftToBridge
                        : srcAccountBalances[j].balance;
                    amountLeftToBridge -= amountToBridge;

                    (quarkOperations[actionIndex], actions[actionIndex]) = Actions.bridgeAsset(
                        Actions.BridgeAsset({
                            chainAccountsList: chainAccountsList,
                            assetSymbol: cometSupplyIntent.assetSymbol,
                            amount: amountToBridge,
                            // where it comes from
                            srcChainId: srcChainAccounts.chainId,
                            sender: srcAccountBalances[j].account,
                            // where it goes
                            destinationChainId: cometSupplyIntent.chainId,
                            recipient: cometSupplyIntent.sender,
                            blockTimestamp: cometSupplyIntent.blockTimestamp
                        }),
                        payment,
                        false // XXX pass in an actual value for useQuoteCall
                    );

                    actionIndex++;
                    bridgeActionCount++;
                }
            }

            if (amountLeftToBridge > 0) {
                revert FundsUnavailable(
                    cometSupplyIntent.assetSymbol,
                    cometSupplyIntent.amount - balanceOnDstChain,
                    cometSupplyIntent.amount - balanceOnDstChain - amountLeftToBridge,
                    amountLeftToBridge
                );
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

    // TODO: handle transfer max
    // TODO: support expiry
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

        assertSufficientFunds(transferIntent.assetSymbol, transferIntent.amount, chainAccountsList);
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
        // TODO: actually allocate quark actions
        Actions.Action[] memory actions = new Actions.Action[](chainAccountsList.length);
        IQuarkWallet.QuarkOperation[] memory quarkOperations =
            new IQuarkWallet.QuarkOperation[](2 * chainAccountsList.length);

        if (
            needsBridgedFunds(
                transferIntent.assetSymbol, transferIntent.amount, transferIntent.chainId, chainAccountsList
            )
        ) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = transferIntent.amount;
            // If the payment token is the transfer token and user opt for paying with the payment token, need to add max cost back to the amountLeftToBridge for target chain
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
            if (needsBridgedFunds(payment.currency, maxCostOnDstChain, transferIntent.chainId, chainAccountsList)) {
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

    function assertSufficientFunds(
        string memory assetSymbol,
        uint256 amount,
        Accounts.ChainAccounts[] memory chainAccountsList
    ) internal pure {
        uint256 aggregateTransferAssetBalance;
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            aggregateTransferAssetBalance +=
                Accounts.sumBalances(Accounts.findAssetPositions(assetSymbol, chainAccountsList[i].assetPositionsList));
        }
        // There are not enough aggregate funds on all chains to fulfill the transfer.
        if (aggregateTransferAssetBalance < amount) {
            revert InsufficientFunds(amount, aggregateTransferAssetBalance);
        }
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
        if (!needsBridgedFunds(assetSymbol, amount, chainId, chainAccountsList)) {
            return;
        }

        // Check each chain to see if there are enough transfer assets to be bridged over
        uint256 aggregateTransferAssetAvailableBalance;
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            Accounts.AssetPositions memory positions =
                Accounts.findAssetPositions(assetSymbol, chainAccountsList[i].assetPositionsList);

            if (
                chainAccountsList[i].chainId == chainId
                    || BridgeRoutes.canBridge(chainAccountsList[i].chainId, chainId, assetSymbol)
            ) {
                aggregateTransferAssetAvailableBalance += Accounts.sumBalances(positions);
                // If the user opts for paying with the payment token and the payment token is the transfer token, reduce
                // the available balance by the max cost because the max cost is reserved for paying the txn
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, assetSymbol)) {
                    uint256 maxCost = PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId);
                    aggregateTransferAssetAvailableBalance -= maxCost;
                }
            }
        }

        if (aggregateTransferAssetAvailableBalance < amount) {
            revert FundsUnavailable(
                assetSymbol,
                amount,
                aggregateTransferAssetAvailableBalance,
                amount - aggregateTransferAssetAvailableBalance
            );
        }
    }

    function needsBridgedFunds(
        string memory assetSymbol,
        uint256 amount,
        uint256 chainId,
        Accounts.ChainAccounts[] memory chainAccountsList
    ) internal pure returns (bool) {
        return Accounts.getBalanceOnChain(assetSymbol, chainId, chainAccountsList) < amount;
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
            } else {
                revert InvalidActionType();
            }
        }

        if (paymentTokenCost > (targetChainPaymentTokenBalance + paymentTokenBridgeAmount)) {
            revert MaxCostTooHigh();
        }
    }
}
