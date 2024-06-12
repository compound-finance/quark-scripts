// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";

import {Actions} from "./Actions.sol";
import {Accounts} from "./Accounts.sol";
import {BridgeRoutes} from "./BridgeRoutes.sol";
import {EIP712Helper} from "./EIP712Helper.sol";
import {Strings} from "./Strings.sol";

contract QuarkBuilder {
    /* ===== Constants ===== */

    string constant VERSION = "1.0.0";

    /* ===== Custom Errors ===== */

    error AssetPositionNotFound();
    error FundsUnavailable();
    error InsufficientFunds();
    error InvalidInput();
    error MaxCostTooHigh();

    /* ===== Input Types ===== */

    struct Payment {
        bool isToken;
        // Note: Payment `currency` should be the same across chains
        string currency;
        PaymentMaxCost[] maxCosts;
    }

    struct PaymentMaxCost {
        uint256 chainId;
        uint256 amount;
    }

    /* ===== Output Types ===== */

    struct BuilderResult {
        // version of the builder interface. (Same as VERSION, but attached to the output.)
        string version;
        // array of quark operations to execute to fulfill the client intent
        IQuarkWallet.QuarkOperation[] quarkOperations;
        // array of action context and other metadata corresponding 1:1 with quarkOperations
        Actions.Action[] actions;
        // EIP-712 digest to sign for a MultiQuarkOperation to fulfill the client intent.
        // Empty when quarkOperations.length == 0.
        bytes32 multiQuarkOperationDigest;
        // EIP-712 digest to sign for a single QuarkOperation to fulfill the client intent.
        // Empty when quarkOperations.length != 1.
        bytes32 quarkOperationDigest;
        // client-provided paymentCurrency string that was used to derive token addresses.
        // client may re-use this string to construct a request that simulates the transaction.
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
        Payment memory payment
    ) external pure returns (BuilderResult memory) {
        assertSufficientFunds(transferIntent, chainAccountsList);
        assertFundsAvailable(transferIntent, chainAccountsList);
        assertPaymentAffordable(transferIntent, chainAccountsList, payment);

        /*
         * at most one bridge operation per non-destination chain,
         * and at most one transferIntent operation on the destination chain.
         *
         * therefore the upper bound is chainAccountsList.length.
         */
        uint256 actionIndex = 0;
        // TODO: actually allocate quark actions
        Actions.Action[] memory actions = new Actions.Action[](chainAccountsList.length);
        IQuarkWallet.QuarkOperation[] memory quarkOperations =
            new IQuarkWallet.QuarkOperation[](chainAccountsList.length);

        if (needsBridgedFunds(transferIntent, chainAccountsList)) {
            // TODO: actually enumerate chain accounts other than the destination chain,
            // and check balances and choose amounts to send and from which.
            //
            // for now: simplify!
            // only check 8453 (Base mainnet);
            //   check every account;
            //     sum the balances and if there's enough to cover the gap,
            //     bridge from each account in arbitrary order of appearance
            //     until there is enough.
            if (payment.isToken) {
                // wrap around paycall
                // TODO: need to embed price feed addresses for known tokens before we can do paycall.
                // ^^^ look up USDC price feeds for each supported chain?
                // we only need USDC/USD and only on chains 1 (mainnet) and 8453 (base mainnet).
            } else {
                quarkOperations[actionIndex++] = Actions.bridgeUSDC(
                    Actions.BridgeUSDC({
                        chainAccountsList: chainAccountsList,
                        assetSymbol: transferIntent.assetSymbol,
                        amount: transferIntent.amount,
                        // where it comes from
                        originChainId: 8453, // FIXME: originChainId
                        sender: address(0), // FIXME: sender
                        // where it goes
                        destinationChainId: transferIntent.chainId,
                        recipient: transferIntent.recipient,
                        blockTimestamp: transferIntent.blockTimestamp
                    })
                );
                // TODO: also append a Actions.Action to the actions array.
                // See: BridgeUSDC TODO for returning a Actions.Action.
            }
        }

        // Then, transferIntent `amount` of `assetSymbol` to `recipient`
        // TODO: construct action contexts
        if (payment.isToken) {
            // wrap around paycall
        } else {
            (quarkOperations[actionIndex], actions[actionIndex]) = Actions.transferAsset(
                Actions.TransferAsset({
                    chainAccountsList: chainAccountsList,
                    assetSymbol: transferIntent.assetSymbol,
                    amount: transferIntent.amount,
                    chainId: transferIntent.chainId,
                    sender: transferIntent.sender,
                    recipient: transferIntent.recipient,
                    blockTimestamp: transferIntent.blockTimestamp
                })
            );
            actionIndex++;
        }

        // Construct EIP712 digests
        // We leave `multiQuarkOperationDigest` empty if there is only a single QuarkOperation
        // We leave `quarkOperationDigest` if there are more than one QuarkOperations
        actions = truncate(actions, actionIndex);
        quarkOperations = truncate(quarkOperations, actionIndex);
        bytes32 quarkOperationDigest;
        bytes32 multiQuarkOperationDigest;
        if (quarkOperations.length == 1) {
            quarkOperationDigest =
                EIP712Helper.getDigestForQuarkOperation(quarkOperations[0], actions[0].quarkAccount, actions[0].chainId);
        } else if (quarkOperations.length > 1) {
            multiQuarkOperationDigest = EIP712Helper.getDigestForMultiQuarkOperation(quarkOperations, actions);
        }

        return BuilderResult({
            version: VERSION,
            actions: actions,
            quarkOperations: quarkOperations,
            paymentCurrency: payment.currency,
            multiQuarkOperationDigest: multiQuarkOperationDigest,
            quarkOperationDigest: quarkOperationDigest
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
            revert InsufficientFunds();
        }
    }

    // For some reason, funds that may otherwise be bridgeable or held by the
    // user cannot be made available to fulfill the transaction. Funds cannot
    // be bridged, e.g. no bridge exists Funds cannot be withdrawn from comet,
    // e.g. no reserves In order to consider the availability here, we’d need
    // comet data to be passed in as an input. (So, if we were including
    // withdraw.)
    function assertFundsAvailable(
        TransferIntent memory transferIntent,
        Accounts.ChainAccounts[] memory chainAccountsList
    ) internal pure {
        if (needsBridgedFunds(transferIntent, chainAccountsList)) {
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
                }
            }
            if (aggregateTransferAssetAvailableBalance < transferIntent.amount) {
                revert FundsUnavailable();
            }
        }
    }

    function needsBridgedFunds(TransferIntent memory transferIntent, Accounts.ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (bool)
    {
        Accounts.AssetPositions memory localPositions =
            Accounts.findAssetPositions(transferIntent.assetSymbol, transferIntent.chainId, chainAccountsList);
        return Accounts.sumBalances(localPositions) < transferIntent.amount;
    }

    // Assert that each chain has sufficient funds to cover the max cost for that chain.
    // NOTE: This check assumes we will not be bridging payment tokens for the user.
    function assertPaymentAffordable(
        TransferIntent memory transferIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        Payment memory payment
    ) internal pure {
        if (payment.isToken) {
            for (uint256 i = 0; i < payment.maxCosts.length; ++i) {
                uint256 paymentAssetBalanceOnChain = Accounts.sumBalances(
                    Accounts.findAssetPositions(payment.currency, payment.maxCosts[i].chainId, chainAccountsList)
                );
                uint256 paymentAssetNeeded = payment.maxCosts[i].amount;
                // If the payment token is the transfer token and this is the
                // target chain, we need to account for the transfer amount
                // when checking token balances
                if (
                    Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)
                        && transferIntent.chainId == payment.maxCosts[i].chainId
                ) {
                    paymentAssetNeeded += transferIntent.amount;
                }
                if (paymentAssetBalanceOnChain < paymentAssetNeeded) {
                    revert MaxCostTooHigh();
                }
            }
        }
    }

    function truncate(Actions.Action[] memory actions, uint256 length)
        internal
        pure
        returns (Actions.Action[] memory)
    {
        Actions.Action[] memory result = new Actions.Action[](length);
        for (uint256 i = 0; i < length; ++i) {
            result[i] = actions[i];
        }
        return result;
    }

    function truncate(IQuarkWallet.QuarkOperation[] memory operations, uint256 length)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation[] memory)
    {
        IQuarkWallet.QuarkOperation[] memory result = new IQuarkWallet.QuarkOperation[](length);
        for (uint256 i = 0; i < length; ++i) {
            result[i] = operations[i];
        }
        return result;
    }
}
