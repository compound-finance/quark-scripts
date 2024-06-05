// SPDX-License-Identifier: BSD-3-Clause
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

    string constant PAYMENT_CURRENCY_USD = "usd";
    string constant PAYMENT_CURRENCY_USDC = "usdc";

    /* ===== Custom Errors ===== */

    error AssetPositionNotFound();
    error BridgeNotFound(uint256 srcChainId, uint256 dstChainId, string assetSymbol);
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

    /* ===== Internal/Intermediate Types ===== */

    // Note: This is just the AssetPositions type with an extra `chainId` field
    struct AssetPositionsWithChainId {
        uint256 chainId;
        address asset;
        string symbol;
        uint256 decimals;
        uint256 usdPrice;
        AccountBalance[] accountBalances;
    }

    function filterAssetPositions(string memory assetSymbol, ChainAccounts[] memory chainAccountsList) internal pure returns (AssetPositionsWithChainId[] memory) {
        uint numMatches = 0;
        // First loop to count the number of matching AssetPositions
        for (uint i = 0; i < chainAccountsList.length; ++i) {
            for (uint j = 0; j < chainAccountsList[i].assetPositionsList.length; ++j) {
                if (Strings.stringEqIgnoreCase(chainAccountsList[i].assetPositionsList[j].symbol, assetSymbol)) {
                    numMatches++;
                }
            }
        }

        AssetPositionsWithChainId[] memory matchingAssetPositions = new AssetPositionsWithChainId[](numMatches);
        uint index = 0;
        // Second loop to populate the matchingAssetPositions array
        for (uint i = 0; i < chainAccountsList.length; ++i) {
            for (uint j = 0; j < chainAccountsList[i].assetPositionsList.length; ++j) {
                if (Strings.stringEqIgnoreCase(chainAccountsList[i].assetPositionsList[j].symbol, assetSymbol)) {
                    AssetPositions memory assetPositions = chainAccountsList[i].assetPositionsList[j];
                    matchingAssetPositions[index] = AssetPositionsWithChainId({
                        chainId: chainAccountsList[i].chainId,
                        asset: assetPositions.asset,
                        symbol: assetPositions.symbol,
                        decimals: assetPositions.decimals,
                        usdPrice: assetPositions.usdPrice,
                        accountBalances: assetPositions.accountBalances
                    });
                    index++;
                }
            }
        }

        return matchingAssetPositions;
    }

    function getAssetPositionsForSymbolAndChain(string memory assetSymbol, uint256 chainId, ChainAccounts[] memory chainAccountsList) internal pure returns (AssetPositionsWithChainId memory) {
        uint index = 0;
        // Second loop to populate the matchingAssetPositions array
        for (uint i = 0; i < chainAccountsList.length; ++i) {
            if (chainAccountsList[i].chainId != chainId) {
                continue;
            }
            for (uint j = 0; j < chainAccountsList[i].assetPositionsList.length; ++j) {
                if (Strings.stringEqIgnoreCase(chainAccountsList[i].assetPositionsList[j].symbol, assetSymbol)) {
                    AssetPositions memory assetPositions = chainAccountsList[i].assetPositionsList[j];
                    return AssetPositionsWithChainId({
                        chainId: chainAccountsList[i].chainId,
                        asset: assetPositions.asset,
                        symbol: assetPositions.symbol,
                        decimals: assetPositions.decimals,
                        usdPrice: assetPositions.usdPrice,
                        accountBalances: assetPositions.accountBalances
                    });
                }
            }
        }

        revert AssetPositionNotFound();
    }

    function sumBalances(AssetPositionsWithChainId memory assetPositions) internal pure returns (uint256) {
        uint256 totalBalance = 0;
        for (uint j = 0; j < assetPositions.accountBalances.length; ++j) {
            totalBalance += assetPositions.accountBalances[j].balance;
        }
        return totalBalance;
    }

    // TODO: handle transfer max
    // TODO: support expiry
    function transfer(
        uint256 chainId,
        string assetSymbol,
        uint256 amount,
        address recipient,
        Payment calldata payment,
        ChainAccounts[] calldata chainAccountsList
    ) external pure returns (BuilderResult memory) {
        AssetPositionsWithChainId[] transferAssetPositions = filterAssetPositions(assetSymbol, chainAccountsList);
        AssetPositionsWithChainId[] paymentAssetPositions;
        if (payment.isToken) {
            paymentAssetPositions = filterAssetPositions(payment.currency, chainAccountsList);
        }

        // INSUFFICIENT_FUNDS
        // There are not enough aggregate funds on all chains to fulfill the transfer.
        uint256 aggregateTransferAssetBalance;
        for (uint i = 0; i < transferAssetPositions.length; ++i) {
            for (uint j = 0; j < transferAssetPositions[i].accountBalances.length; ++j) {
                aggregateTransferAssetBalance += transferAssetPositions[i].accountBalances[j].balance;
            }
        }
        if (aggregateTransferAssetBalance < amount) {
            revert InsufficientFunds();
        }

        // TODO: Pay with bridged payment.currency?
        // MAX_COST_TOO_HIGH
        // There is at least one chain that does not have sufficient payment assets to cover the maxCost for that chain.
        // Note: This check assumes we will not be bridging payment tokens for the user
        if (payment.isToken) {
            for (uint i = 0; i < payment.maxCosts.length; ++i) {
                PaymentMaxCost memory maxCost = payment.maxCosts[i];
                AssetPositionsWithChainId memory paymentAssetPosition = getAssetPositionsForSymbolAndChain(payment.currency, maxCost.chainId, chainAccountsList);
                uint256 paymentAssetBalanceOnChain = sumBalances(paymentAssetPosition);
                uint256 paymentAssetNeeded = maxCost.amount;
                // If the payment token is the transfer token and this is the target chain, we need to account for the transfer amount when checking token balances
                if (Strings.stringEqIgnoreCase(payment.currency, assetSymbol) && chainId == maxCost.chainId) {
                    paymentAssetNeeded += amount;
                }
                if (paymentAssetBalanceOnChain < paymentAssetNeeded) {
                    revert MaxCostTooHigh();
                }
            }
        }

        // FUNDS_UNAVAILABLE
        // For some reason, funds that may otherwise be bridgeable or held by the user cannot be made available to fulfill the transaction.
        // Funds cannot be bridged, e.g. no bridge exists
        // Funds cannot be withdrawn from comet, e.g. no reserves
        // In order to consider the availability here, we’d need comet data to be passed in as an input. (So, if we were including withdraw.)
        uint256 aggregateTransferAssetAvailableBalance;
        for (uint i = 0; i < transferAssetPositions.length; ++i) {
            uint256 srcChainId = transferAssetPositions[i].chainId;
            for (uint j = 0; j < transferAssetPositions[i].accountBalances.length; ++j) {
                if (BridgeRoutes.hasBridge(srcChainId, chainId, assetSymbol)) {
                    aggregateTransferAssetAvailableBalance += transferAssetPositions[i].accountBalances[j].balance;
                }
            }
        }
        if (aggregateTransferAssetBalance < amount) {
            revert FundsUnavailable();
        }

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
        IQuarkWallet.QuarkOperation memory bridgeQuarkOperation;
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
                bridgeQuarkOperation = IQuarkWallet.QuarkOperation({
                    nonce: 0, // TODO: get next nonce
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
        IQuarkWallet.QuarkOperation memory transferQuarkOperation;
        // TODO: don't necessarily need scriptSources
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(TransferActions).creationCode;
        // TODO: construct action contexts
        if (assetSymbol == "ETH") {
            if (payment.isToken) {
                // wrap around paycall
            } else {
                address scriptAddress = getCodeAddress(codeJar, type(TransferActions).creationCode);
                // Native ETH transfer
                transferQuarkOperation = IQuarkWallet.QuarkOperation({
                    nonce: 0, // TODO: get next nonce
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
                transferQuarkOperation = IQuarkWallet.QuarkOperation({
                    nonce: 0, // TODO: get next nonce
                    chainId: chainId,
                    scriptAddress: scriptAddress,
                    scriptCalldata: abi.encodeWithSelector(TransferActions.transferERC20Token.selector, token, recipient, amount),
                    scriptSources: scriptSources,
                    expiry: 99999999999 // TODO: never expire?
                });
            }
        }

        // TODO: construct QuarkOperation of size 1 or 2 depending on bridge or not
        // return QuarkAction({
        //     version: version,
        //     actionType: actionType,
        //     actionContext: actionContext,
        //     operations: operations
        // });

        return BuilderResult({
            version: VERSION,
            quarkOperations: new IQuarkWallet.QuarkOperation[](0),
            quarkActions: new QuarkAction[](0),
            multiQuarkOperationDigest: bytes(0),
            quarkOperationDigest: bytes(0),
            paymentCurrency: payment.currency
        });
    }
}


// 1. Input validation (custom errors)
// 2. Constructing the operation
//   a) Bridge operation (conditional)
//   b) Wrap around Paycall/Quotecall (conditional)
//   c) Transfer operation (non-conditional)
// 3. Constructing the BuilderResult (action contexts, eip-712 digest)