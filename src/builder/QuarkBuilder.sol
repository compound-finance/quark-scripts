// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {TransferActions} from "../DeFiScripts.sol";

contract QuarkBuilder {
    string constant VERSION = "1";

    // TODO: move to Builder implementation
    string constant PAYMENT_METHOD_OFFCHAIN = "OFFCHAIN";
    string constant PAYMENT_METHOD_PAYCALL = "PAY_CALL";
    string constant PAYMENT_METHOD_QUOTECALL = "QUOTE_CALL";

    string constant ACTION_TYPE_BRIDGE = "BRIDGE";
    string constant ACTION_TYPE_TRANSFER = "TRANSFER";

    string constant PAYMENT_CURRENCY_USD = "usd";
    string constant PAYMENT_CURRENCY_USDC = "usdc";

    error InsufficientFunds();
    error MaxCostTooHigh();

    struct BuilderResult {
        // version of the builder interface. (Same as VERSION, but attached to the output.)
        string version;
        // array of quark operations to execute to fulfill the client intent
        QuarkWallet.QuarkOperation[] quarkOperations;
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
        uint256 quarkNextNonce;
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
        string currency;
        uint256[] chainIds;
        uint256[] maxCosts;
    }

    function getPriceFeed(string assetSymbol, uint256 chaindId) internal pure (address) {

    }

    // TODO: handle transfer max
    function transfer(
        uint256 chainId,
        string assetSymbol,
        uint256 amount,
        address recipient,
        Payment calldata payment,
        ChainAccounts[] calldata chainAccountsList
    ) external pure returns (BuilderResult memory) {
        // TODO: Input validation: Check that arrays are equal length (e.g. chainIds and maxCosts in Payment)
        AssetPositions[] paymentAssetAccounts;
        // Get transfer and payment token
        // TODO: implement filterAccounts
        transferAssetAccounts = filterAccounts(assetSymbol, chainAccountsList);
        if (payment.isToken) {
            paymentAssetAccounts = filterAccounts(payment.currency, chainAccountsList);
        }

        // INSUFFICIENT_FUNDS
        // There are not enough funds to fulfill the transfer.
        // aggregate amount of asset on every chain < transfer amount
        uint256 transferAssetBalance;
        for (uint i = 0; i < transferAssetAccounts.length; ++i) {
            for (uint j = 0; j < transferAssetAccounts[i].accountBalances.length; ++j) {
                transferAssetBalance += transferAssetAccounts[i].accountBalances[j].balance;
            }
        }
        if (transferAssetBalance < amount) {
            revert InsufficientFunds();
        }

        // MAX_COST_TOO_HIGH
        // There are not enough funds to satisfy the total max payment cost, after transferring.
        // (amount of payment token on chain id - transfer amount (IF IS SAME TOKEN AND SAME CHAIN ID)) < maxPaymentAmount on chain id
        for (uint i = 0; i < payment.maxCosts.length; ++i) {
            paymentAssetBalanceOnChain = getBalanceOnChain(payment.currency, payment.chainIds[i], chainAccountsList);
            if (payment.currency == assetSymbol && chainId == payment.chainIds[i]) {
                // TODO: this could underflow
                paymentAssetBalanceOnChain -= transferAmount;
            }
            if (paymentAssetBalanceOnChain < payment.maxCosts[i]) {
                revert MaxCostTooHigh();
            }
        }

        // FUNDS_UNAVAILABLE
        // For some reason, funds that may otherwise be bridgeable or held by the user cannot be made available to fulfill the transaction.
        // Funds cannot be bridged, e.g. no bridge exists
        // Funds cannot be withdrawn from comet, e.g. no reserves
        // In order to consider the availability here, we’d need comet data to be passed in as an input. (So, if we were including withdraw.)


        // Construct Quark Operations:

        // If Payment.isToken:
            // Wrap Quark operation around a Paycall/Quotecall
            // Process for generating Paycall transaction:

        // We need to find the (payment token address, payment token price feed address) to derive the CREATE2 address of the Paycall script
        // TODO: define helper function to get (payment token address, payment token price feed address) given a chain ID

        // TODO:
        // If not enough assets on the chain ID:
            // Then bridging is required AND/OR withdraw from Comet is required
            // Prepend a bridge action to the list of actions
            // Bridge `amount` of `chainAsset` to `recipient`
        QuarkOperation memory bridgeQuarkOperation;
        // TODO: implement get assetBalanceOnChain
        uint256 transferAssetBalanceOnTargetChain = getAssetBalanceOnChain(assetSymbol, chainId, chainAccountsList);
        // Note: User will always have enough payment token on destination chain, since we already check that in the MaxCostTooHigh() check
        if (transferAssetBalanceOnTargetChain < amount) {
            // Construct bridge operation if not enough funds on target chain
            // TODO: bridge routing logic (which bridge to prioritize, how many bridges?)

            // TODO: construct action contexts
            if (payment.isToken) {
                // wrap around paycall
            } else {
                address scriptAddress = getCodeAddress(codeJar, type(BridgeActions).creationCode);
                bridgeQuarkOperation = QuarkOperation({
                    nonce: , // TODO: get next nonce
                    chainId: chainId,
                    scriptAddress: scriptAddress,
                    // TODO: Do we have a bridge action script?
                    scriptCalldata: abi.encodeWithSelector(BridgeActions.bridge.selector, recipient, amount),
                    scriptSources: scriptSources,
                    expiry: 99999999999 // TODO: never expire?
                });
            }
        }

        // Then, transfer `amount` of `chainAsset` to `recipient`
        QuarkOperation memory transferQuarkOperation;
        address scriptAddress = getCodeAddress(codeJar, type(TransferActions).creationCode);
        // TODO: don't necessarily need scriptSources
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(TransferActions).creationCode;
        // TODO: construct action contexts
        if (assetSymbol == "ETH") {
            if (payment.isToken) {
                // wrap around paycall
            } else {
                // Native ETH transfer
                transferQuarkOperation = QuarkOperation({
                    nonce: , // TODO: get next nonce
                    chainId: chainId,
                    scriptAddress: scriptAddress,
                    scriptCalldata: abi.encodeWithSelector(TransferActions.transferNativeToken.selector, recipient, amount),
                    scriptSources: scriptSources,
                    expiry: 99999999999 // TODO: never expire?
                });
            }
        } else {
            if (payment.isToken) {
                // wrap around paycall
            } else {
                // ERC20 transfer
                transferQuarkOperation = QuarkOperation({
                    nonce: , // TODO: get next nonce
                    chainId: chainId,
                    scriptAddress: scriptAddress,
                    scriptCalldata: abi.encodeWithSelector(TransferActions.transferERC20Token.selector, token, recipient, amount),
                    scriptSources: scriptSources,
                    expiry: 99999999999 // TODO: never expire?
                });
            }
        }

        // TODO: construct QuarkOperation of size 1 or 2 depending on bridge or not
        QuarkOperation[] memory operations = new QuarkOperation[](1);
        return QuarkAction({
            version: version,
            actionType: actionType,
            actionContext: actionContext,
            operations: operations
        });
        // TODO: return these
        struct BuilderResult {
            // version of the builder interface. (Same as VERSION, but attached to the output.)
            string version;
            // array of quark operations to execute to fulfill the client intent
            QuarkWallet.QuarkOperation[] quarkOperations;
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
            string actionType;
            bytes actionContext;
            // One of the PAYMENT_METHOD_* constants.
            string paymentMethod;
            // Address of payment token on chainId.
            // Null address if the payment method was OFFCHAIN.
            address paymentToken;
            uint256 paymentMaxCost;
        }
    }
}


// 1. Input validation (custom errors)
// 2. Constructing the operation
//   a) Bridge operation (conditional)
//   b) Wrap around Paycall/Quotecall (conditional)
//   c) Transfer operation (non-conditional)
// 3. Constructing the BuilderResult (action contexts, eip-712 digest)
