// SPDX-License-Identifier: BSD-3-Clause
//
pragma solidity ^0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {TransferActions} from "../DeFiScripts.sol";

import "./BridgeRoutes.sol";
import "./Strings.sol";

contract QuarkBuilder {
    /* ===== Constants ===== */
    string constant VERSION = "1.0.0";

    string constant PAYMENT_METHOD_OFFCHAIN = "OFFCHAIN";
    string constant PAYMENT_METHOD_PAYCALL = "PAY_CALL";
    string constant PAYMENT_METHOD_QUOTECALL = "QUOTE_CALL";

    string constant ACTION_TYPE_BRIDGE = "BRIDGE";
    string constant ACTION_TYPE_TRANSFER = "TRANSFER";

    /* ===== Custom Errors ===== */

    error AssetPositionNotFound();
    error FundsUnavailable();
    error InsufficientFunds();
    error InvalidInput();
    error MaxCostTooHigh();

    /* ===== Input Types ===== */

    struct ChainAccounts {
        uint256 chainId;
        QuarkState[] quarkStates;
        AssetPositions[] assetPositionsList;
    }

    // We map this to the Portfolio data structure that the client will already have.
    // This includes fields that builder may not necessarily need, however it makes
    // the client encoding that much simpler.
    struct QuarkState {
        address account;
        bool hasCode;
        bool isQuark;
        string quarkVersion;
        uint96 quarkNextNonce;
    }

    // Similarly, this is designed to intentionally reduce the encoding burden for the client
    // by making it equivalent in structure to data already in portfolios.
    struct AssetPositions {
        address asset;
        string symbol;
        uint256 decimals;
        uint256 usdPrice;
        AccountBalance[] accountBalances;
    }

    struct AccountBalance {
        address account;
        uint256 balance;
    }

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
        QuarkAction[] quarkActions;
        // EIP-712 digest to sign for a MultiQuarkOperation to fulfill the client intent.
        // Empty when quarkOperations.length == 0.
        bytes multiQuarkOperationDigest;
        // EIP-712 digest to sign for a single QuarkOperation to fulfill the client intent.
        // Empty when quarkOperations.length != 1.
        bytes quarkOperationDigest;
        // client-provided paymentCurrency string that was used to derive token addresses.
        // client may re-use this string to construct a request that simulates the transaction.
        string paymentCurrency;
    }

    // With QuarkAction, we try to define fields that are as 1:1 as possible with the
    // simulate endpoint request schema.
    struct QuarkAction {
        uint256 chainId;
        address quarkAccount;
        string actionType;
        bytes actionContext;
        // One of the PAYMENT_METHOD_* constants.
        string paymentMethod;
        // Address of payment token on chainId.
        // Null address if the payment method was OFFCHAIN.
        address paymentToken;
        uint256 paymentMaxCost;
    }

    struct TransferActionContext {
        uint256 amount;
        uint256 price;
        address token;
        uint256 chainId;
        address recipient;
    }

    struct BridgeActionContext {
        uint256 amount;
        uint256 price;
        address token;
        uint256 chainId;
        address recipient;
        uint256 destinationChainId;
    }

    /* ===== Helper Functions ===== */

    function codeJar(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) {
            return address(0xff); // FIXME
        } else {
            revert(); // FIXME
        }
    }

    function getCodeAddress(uint256 chainId, bytes memory code) public pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), codeJar(chainId), uint256(0), keccak256(code)))))
        );
    }

    function findChainAccounts(uint256 chainId, ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (ChainAccounts memory found)
    {
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            if (chainAccountsList[i].chainId == chainId) {
                return found = chainAccountsList[i];
            }
        }
    }

    function findAssetPositions(string memory assetSymbol, AssetPositions[] memory assetPositionsList)
        internal
        pure
        returns (AssetPositions memory found)
    {
        for (uint256 i = 0; i < assetPositionsList.length; ++i) {
            if (Strings.stringEqIgnoreCase(assetSymbol, assetPositionsList[i].symbol)) {
                return found = assetPositionsList[i];
            }
        }
    }

    function findAssetPositions(string memory assetSymbol, uint256 chainId, ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (AssetPositions memory found)
    {
        ChainAccounts memory chainAccounts = findChainAccounts(chainId, chainAccountsList);
        return findAssetPositions(
            assetSymbol,
            chainAccounts.assetPositionsList
        );
    }

    function findQuarkState(address account, QuarkState[] memory quarkStates)
        internal
        pure
        returns (QuarkState memory state)
    {
        for (uint256 i = 0; i < quarkStates.length; ++i) {
            if (quarkStates[i].account == account) {
                return state = quarkStates[i];
            }
        }
    }

    function sumBalances(AssetPositions memory assetPositions) internal pure returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 j = 0; j < assetPositions.accountBalances.length; ++j) {
            totalBalance += assetPositions.accountBalances[j].balance;
        }
        return totalBalance;
    }

    /* ===== Main Implementation ===== */

    struct TransferIntent {
        uint256 chainId;
        string assetSymbol;
        uint256 amount;
        address sender;
        address recipient;
    }

    // TODO: handle transfer max
    // TODO: support expiry
    function transfer(
        TransferIntent memory transferIntent,
        ChainAccounts[] memory chainAccountsList,
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
        QuarkAction[] memory quarkActions = new QuarkAction[](chainAccountsList.length);
        IQuarkWallet.QuarkOperation[] memory quarkOperations = new IQuarkWallet.QuarkOperation[](chainAccountsList.length);

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
                quarkOperations[actionIndex++] = BridgeUSDC(
                    BridgeUSDCInput({
                        chainAccountsList: chainAccountsList,
                        assetSymbol: transferIntent.assetSymbol,
                        amount: transferIntent.amount,
                        // where it comes from
                        originChainId: 8453, // FIXME: originChainId
                        sender: address(0),  // FIXME: sender
                        // where it goes
                        destinationChainId: transferIntent.chainId,
                        recipient: transferIntent.recipient
                    })
                );
                // TODO: also append a QuarkAction to the quarkActions array.
                // See: BridgeUSDC TODO for returning a QuarkAction.
            }
        }

        // Then, transferIntent `amount` of `assetSymbol` to `recipient`
        // TODO: construct action contexts
        if (payment.isToken) {
            // wrap around paycall
        } else {
            quarkOperations[actionIndex++] = AssetTransfer(
                AssetTransferInput({
                    chainAccountsList: chainAccountsList,
                    assetSymbol: transferIntent.assetSymbol,
                    amount: transferIntent.amount,
                    chainId: transferIntent.chainId,
                    sender: transferIntent.sender,
                    recipient: transferIntent.recipient
                })
            );
        }

        return BuilderResult({
            version: VERSION,
            quarkOperations: quarkOperations,
            quarkActions: quarkActions,
            paymentCurrency: payment.currency,
            // TODO: construct actual digests
            multiQuarkOperationDigest: new bytes(0),
            // TODO: construct actual digests
            quarkOperationDigest: new bytes(0)
        });
    }

    function assertSufficientFunds(
        TransferIntent memory transferIntent,
        ChainAccounts[] memory chainAccountsList
    ) internal pure {
        uint256 aggregateTransferAssetBalance;
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            aggregateTransferAssetBalance +=
                sumBalances(
                    findAssetPositions(
                        transferIntent.assetSymbol,
                        chainAccountsList[i].assetPositionsList
                    )
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
        ChainAccounts[] memory chainAccountsList
    ) internal pure {
        if (needsBridgedFunds(transferIntent, chainAccountsList)) {
            uint256 aggregateTransferAssetAvailableBalance;
            for (uint256 i = 0; i < chainAccountsList.length; ++i) {
                AssetPositions memory positions = findAssetPositions(
                    transferIntent.assetSymbol,
                    chainAccountsList[i].assetPositionsList
                );
                if (chainAccountsList[i].chainId == transferIntent.chainId
                    || BridgeRoutes.canBridge(chainAccountsList[i].chainId, transferIntent.chainId, transferIntent.assetSymbol)) 
                {
                    aggregateTransferAssetAvailableBalance += sumBalances(positions);
                }
            }
            if (aggregateTransferAssetAvailableBalance < transferIntent.amount) {
                revert FundsUnavailable();
            }
        }
    }

    function needsBridgedFunds(
        TransferIntent memory transferIntent,
        ChainAccounts[] memory chainAccountsList
    ) internal pure returns (bool) {
        AssetPositions memory localPositions = findAssetPositions(
            transferIntent.assetSymbol,
            transferIntent.chainId,
            chainAccountsList
        );
        return sumBalances(localPositions) < transferIntent.amount;
    }

    // Assert that each chain has sufficient funds to cover the max cost for that chain.
    // NOTE: This check assumes we will not be bridging payment tokens for the user.
    function assertPaymentAffordable(
        TransferIntent memory transferIntent,
        ChainAccounts[] memory chainAccountsList,
        Payment memory payment
    ) internal pure {
        if (payment.isToken) {
            for (uint256 i = 0; i < payment.maxCosts.length; ++i) {
                uint256 paymentAssetBalanceOnChain = sumBalances(
                    findAssetPositions(
                        payment.currency,
                        payment.maxCosts[i].chainId,
                        chainAccountsList
                    )
                );
                uint256 paymentAssetNeeded = payment.maxCosts[i].amount;
                // If the payment token is the transfer token and this is the
                // target chain, we need to account for the transfer amount
                // when checking token balances
                if (Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)
                    && transferIntent.chainId == payment.maxCosts[i].chainId)
                {
                    paymentAssetNeeded += transferIntent.amount;
                }
                if (paymentAssetBalanceOnChain < paymentAssetNeeded) {
                    revert MaxCostTooHigh();
                }
            }
        }
    }


    struct AssetTransferInput {
        ChainAccounts[] chainAccountsList;
        string assetSymbol;
        uint256 amount;
        uint256 chainId;
        address sender;
        address recipient;
    }

    function AssetTransfer(AssetTransferInput memory assetTransferInput)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory/*, QuarkAction memory*/)
    {
        // TODO: create quark action and return as well
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(TransferActions).creationCode;

        ChainAccounts memory accounts =
            findChainAccounts(assetTransferInput.chainId, assetTransferInput.chainAccountsList);

        AssetPositions memory assetPositions =
            findAssetPositions(assetTransferInput.assetSymbol, accounts.assetPositionsList);

        QuarkState memory accountState =
            findQuarkState(assetTransferInput.sender, accounts.quarkStates);

        bytes memory scriptCalldata;
        if (Strings.stringEqIgnoreCase(assetTransferInput.assetSymbol, "ETH")) {
            // Native token transfer
            scriptCalldata = abi.encodeWithSelector(
                TransferActions.transferNativeToken.selector,
                assetTransferInput.recipient,
                assetTransferInput.amount
            );
        } else {
            // ERC20 transfer
            scriptCalldata = abi.encodeWithSelector(
                TransferActions.transferERC20Token.selector,
                assetPositions.asset,
                assetTransferInput.recipient,
                assetTransferInput.amount
            );
        }

        return IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: getCodeAddress(
                assetTransferInput.chainId,
                type(TransferActions).creationCode
            ),
            scriptCalldata: scriptCalldata,
            scriptSources: scriptSources,
            expiry: 99999999999 // TODO: handle expiry
        });
    }

    struct BridgeUSDCInput {
        ChainAccounts[] chainAccountsList;
        string assetSymbol;
        uint256 amount;
        uint256 originChainId;
        address sender;
        uint256 destinationChainId;
        address recipient;
    }

    function BridgeUSDC(BridgeUSDCInput memory bridgeInput)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory/*, QuarkAction memory*/)
    {
        ChainAccounts memory originChainAccounts =
            findChainAccounts(bridgeInput.originChainId, bridgeInput.chainAccountsList);

        AssetPositions memory bridgeAssetPositions =
            findAssetPositions(bridgeInput.assetSymbol, originChainAccounts.assetPositionsList);

        QuarkState memory accountState =
            findQuarkState(bridgeInput.sender, originChainAccounts.quarkStates);

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = CCTP.bridgeScriptSource();

        // CCTP bridge
        return IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: getCodeAddress(bridgeInput.originChainId, scriptSources[0]),
            scriptCalldata: CCTP.encodeBridgeUSDC(
                bridgeInput.originChainId,
                bridgeInput.destinationChainId,
                bridgeInput.amount,
                bridgeInput.recipient,
                bridgeAssetPositions.asset
            ),
            scriptSources: scriptSources,
            expiry: 99999999999 // TODO: handle expiry
        });
    }
}
