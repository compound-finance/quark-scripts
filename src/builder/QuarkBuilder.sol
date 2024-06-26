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
    uint256 constant MAX_BRIDGE_ACTION = 1;

    /* ===== Custom Errors ===== */

    error AssetPositionNotFound();
    error FundsUnavailable(uint256 requiredAmount, uint256 actualAmount, uint256 missingAmount);
    error InsufficientFunds(uint256 requiredAmount, uint256 actualAmount);
    error InvalidInput();
    error MaxCostTooHigh();
    error TooManyBridgeOperations();
    error InvalidActionType();

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

        assertSufficientFunds(transferIntent, chainAccountsList);
        assertFundsAvailable(transferIntent, chainAccountsList, payment);

        /*
         * at most one bridge operation per non-destination chain,
         * and at most one transferIntent operation on the destination chain.
         *
         * therefore the upper bound is chainAccountsList.length.
         */
        uint256 actionIndex = 0;

        // TransferMax will always use quotecall to avoid leaving dust in wallet
        bool useQuotecall = isMaxTransfer;
        // TODO: actually allocate quark actions
        Actions.Action[] memory actions = new Actions.Action[](chainAccountsList.length);
        IQuarkWallet.QuarkOperation[] memory quarkOperations =
            new IQuarkWallet.QuarkOperation[](chainAccountsList.length);

        if (needsBridgedFunds(transferIntent, chainAccountsList)) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 balanceOnDstChain =
                Accounts.getBalanceOnChain(transferIntent.assetSymbol, transferIntent.chainId, chainAccountsList);
            uint256 amountLeftToBridge = transferIntent.amount - balanceOnDstChain;
            // If the payment token is the transfer token and user opt for paying with the payment token, need to add max cost back to the amountLeftToBridge for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)) {
                amountLeftToBridge += PaymentInfo.findMaxCost(payment, transferIntent.chainId);
            }

            uint256 bridgeActionCount = 0;
            // TODO: bridge routing logic (which bridge to prioritize, how many bridges?)
            // Iterate chainAccountList and find upto 2 chains that can provide enough fund
            // Backend can provide optimal routes by adjust the order in chainAccountList.
            for (uint256 i = 0; i < chainAccountsList.length; ++i) {
                // End loop if enough tokens have been bridged
                if (amountLeftToBridge == 0) {
                    break;
                }

                Accounts.ChainAccounts memory srcChainAccounts = chainAccountsList[i];
                // Skip if the current chain is the target chain, since bridging is not possible
                if (srcChainAccounts.chainId == transferIntent.chainId) {
                    continue;
                }

                // Skip if there is no bridge route for the current chain to the target chain
                if (
                    !BridgeRoutes.canBridge(srcChainAccounts.chainId, transferIntent.chainId, transferIntent.assetSymbol)
                ) {
                    continue;
                }

                Accounts.AssetPositions memory srcAssetPositions =
                    Accounts.findAssetPositions(transferIntent.assetSymbol, srcChainAccounts.assetPositionsList);
                Accounts.AccountBalance[] memory srcAccountBalances = srcAssetPositions.accountBalances;
                // TODO: Make logic smarter. Currently, this uses a greedy algorithm.
                // e.g. Optimize by trying to bridge with the least amount of bridge operations
                for (uint256 j = 0; j < srcAccountBalances.length; ++j) {
                    if (bridgeActionCount >= MAX_BRIDGE_ACTION) {
                        revert TooManyBridgeOperations();
                    }

                    uint256 amountToBridge;
                    // Handle differently if the transfer intent token is the payment token
                    if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)) {
                        // Apply payment token logics to figure out the amount to bridge
                        if (
                            srcAccountBalances[j].balance
                                >= amountLeftToBridge + PaymentInfo.findMaxCost(payment, srcChainAccounts.chainId)
                        ) {
                            amountToBridge = amountLeftToBridge;
                        } else {
                            // NOTE: This logics only work when user has only single account on each chain, if having multiple then need to re-adjust to for multi-actions over multi-accounts
                            amountToBridge = srcAccountBalances[j].balance
                                - PaymentInfo.findMaxCost(payment, srcChainAccounts.chainId);
                        }
                    } else {
                        // Apply straightforward logics to bridge the token right away
                        if (srcAccountBalances[j].balance >= amountLeftToBridge) {
                            amountToBridge = amountLeftToBridge;
                        } else {
                            amountToBridge = srcAccountBalances[j].balance;
                        }
                    }

                    amountLeftToBridge -= amountToBridge;

                    (quarkOperations[actionIndex], actions[actionIndex]) = Actions.bridgeAsset(
                        Actions.BridgeAsset({
                            chainAccountsList: chainAccountsList,
                            assetSymbol: transferIntent.assetSymbol,
                            amount: amountToBridge,
                            // where it comes from
                            srcChainId: srcChainAccounts.chainId,
                            sender: srcAccountBalances[j].account,
                            // where it goes
                            destinationChainId: transferIntent.chainId,
                            recipient: transferIntent.sender,
                            blockTimestamp: transferIntent.blockTimestamp
                        }),
                        payment,
                        useQuotecall
                    );

                    actionIndex++;
                    bridgeActionCount++;
                }
            }

            if (amountLeftToBridge > 0) {
                revert FundsUnavailable(
                    transferIntent.amount - balanceOnDstChain,
                    transferIntent.amount - balanceOnDstChain - amountLeftToBridge,
                    amountLeftToBridge
                );
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

        // Truncate actions and quark operations
        actions = Actions.truncate(actions, actionIndex);
        quarkOperations = Actions.truncate(quarkOperations, actionIndex);

        // Validate generated actions for affordability
        assertActionsAffordable(actions, chainAccountsList, transferIntent);

        // Construct EIP712 digests
        EIP712Helper.EIP712Data memory eip712Data;
        bytes32 quarkOperationDigest;
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
        TransferIntent memory transferIntent,
        Accounts.ChainAccounts[] memory chainAccountsList
    ) internal pure {
        uint256 aggregateTransferAssetBalance;
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            aggregateTransferAssetBalance += Accounts.sumBalances(
                Accounts.findAssetPositions(transferIntent.assetSymbol, chainAccountsList[i].assetPositionsList)
            );
        }
        // There are not enough aggregate funds on all chains to fulfill the transfer.
        if (aggregateTransferAssetBalance < transferIntent.amount) {
            revert InsufficientFunds(transferIntent.amount, aggregateTransferAssetBalance);
        }
    }

    // For some reason, funds that may otherwise be bridgeable or held by the user cannot
    // be made available to fulfill the transaction.
    // Funds cannot be bridged, e.g. no bridge exists
    // Funds cannot be withdrawn from Comet, e.g. no reserves
    function assertFundsAvailable(
        TransferIntent memory transferIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure {
        // If no funds need to be bridged, then this check is satisfied
        // TODO: We might still need to check the availability of funds on the target chain, e.g. see if
        // funds are locked in a lending protocol and can't be withdrawn
        if (!needsBridgedFunds(transferIntent, chainAccountsList)) {
            return;
        }

        // Check each chain to see if there are enough transfer assets to be bridged over
        uint256 aggregateTransferAssetAvailableBalance;
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            Accounts.AssetPositions memory positions =
                Accounts.findAssetPositions(transferIntent.assetSymbol, chainAccountsList[i].assetPositionsList);

            if (
                chainAccountsList[i].chainId == transferIntent.chainId
                    || BridgeRoutes.canBridge(
                        chainAccountsList[i].chainId, transferIntent.chainId, transferIntent.assetSymbol
                    )
            ) {
                aggregateTransferAssetAvailableBalance += Accounts.sumBalances(positions);
                // If the user opts for paying with the payment token and the payment token is the transfer token, reduce
                // the available balance by the max cost because the max cost is reserved for paying the txn
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)) {
                    uint256 maxCost = PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId);
                    aggregateTransferAssetAvailableBalance -= maxCost;
                }
            }
        }

        if (aggregateTransferAssetAvailableBalance < transferIntent.amount) {
            revert FundsUnavailable(
                transferIntent.amount,
                aggregateTransferAssetAvailableBalance,
                transferIntent.amount - aggregateTransferAssetAvailableBalance
            );
        }
    }

    function needsBridgedFunds(TransferIntent memory transferIntent, Accounts.ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (bool)
    {
        return Accounts.getBalanceOnChain(transferIntent.assetSymbol, transferIntent.chainId, chainAccountsList)
            < transferIntent.amount;
    }

    // Assert that each chain has sufficient funds to cover the max cost for that chain.
    // Check user account can cover the cost of each actions
    function assertActionsAffordable(
        Actions.Action[] memory actions,
        Accounts.ChainAccounts[] memory chainAccountsList,
        TransferIntent memory transferIntent
    ) internal pure {
        Actions.Action[] memory bridgeActions = Actions.findActionsOfType(actions, Actions.ACTION_TYPE_BRIDGE);
        Actions.Action[] memory transferActions = Actions.findActionsOfType(actions, Actions.ACTION_TYPE_TRANSFER);

        uint256 plannedBridgeAmount = 0;
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

            plannedBridgeAmount += bridgeActionContext.amount;
        }

        // Verify transfer actions are affordable
        // NOTE: Assume all transfer actions are on the TransferIntent.chainId as Bridging logics is currently assuming destination at TransferIntent.chainId
        // NOTE: To support multi-chain transfers, call below functions to check repeatedly with each chainId and plannedBridgeAmount
        // for each chain (Likely passed from TransferIntent with a list of chain Id)
        assertTransferActionsAffordableOnTargetChain(
            transferActions, chainAccountsList, transferIntent.chainId, plannedBridgeAmount
        );
    }

    function assertTransferActionsAffordableOnTargetChain(
        Actions.Action[] memory transferActions,
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 targetChainId,
        uint256 plannedBridgeAmountToTargetChain
    ) internal pure {
        uint256 paymentTokensUsed = 0;
        for (uint256 i = 0; i < transferActions.length; ++i) {
            Actions.TransferActionContext memory transferActionContext =
                abi.decode(transferActions[i].actionContext, (Actions.TransferActionContext));
            // Filter with the targetChainId and paymentTokensUsed will track on one chain at a time
            if (transferActionContext.chainId == targetChainId) {
                address transferToken = transferActionContext.token;
                uint256 transferAmount = transferActionContext.amount;
                uint256 paymentAssetBalanceOnChain = Accounts.sumBalances(
                    Accounts.findAssetPositions(transferToken, transferActions[i].chainId, chainAccountsList)
                );
                paymentTokensUsed += transferActions[i].paymentMaxCost;
                if (transferToken == transferActions[i].paymentToken) {
                    // If the payment token is the transfer token and this is the target chain, we need to account for the transfer amount
                    // If its transfer step, check if user has enough balance to cover the transfer amount after bridge
                    if (
                        paymentAssetBalanceOnChain + plannedBridgeAmountToTargetChain
                            < paymentTokensUsed + transferAmount
                    ) {
                        revert MaxCostTooHigh();
                    }

                    // Special handling as the payment token is sent out so it will be part of the cost
                    paymentTokensUsed += transferAmount;
                } else {
                    // Just check payment token can cover the max cost
                    if (paymentAssetBalanceOnChain < paymentTokensUsed) {
                        revert MaxCostTooHigh();
                    }
                }
            }
        }
    }
}
