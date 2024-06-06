// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {TransferActions} from "../DeFiScripts.sol";
import {CCTPBridgeActions} from "../BridgeScripts.sol";

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

    function filterChainAccounts(string memory assetSymbol, ChainAccounts[] memory chainAccountsList)
        internal
        pure
        returns (ChainAccounts[] memory filtered)
    {
        filtered = new ChainAccounts[](chainAccountsList.length);
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            // NOTE: there can only be one asset positions struct for a given asset on a given chain.
            AssetPositions memory selectedPositions;
            for (uint256 j = 0; j < chainAccountsList[i].assetPositionsList.length; ++j) {
                if (Strings.stringEqIgnoreCase(assetSymbol, chainAccountsList[i].assetPositionsList[j].symbol)) {
                    selectedPositions = chainAccountsList[i].assetPositionsList[j];
                    break;
                }
            }

            AssetPositions[] memory positionsList;
            if (selectedPositions.asset != address(0)) {
                positionsList = new AssetPositions[](1);
                positionsList[0] = selectedPositions;
            }

            filtered[i] = ChainAccounts({
                chainId: chainAccountsList[i].chainId,
                quarkStates: chainAccountsList[i].quarkStates,
                assetPositionsList: positionsList
            });
        }
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

    function sumBalances(AssetPositions memory assetPositions) internal pure returns (uint256) {
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
        string calldata assetSymbol,
        uint256 amount,
        address recipient,
        Payment calldata payment,
        ChainAccounts[] calldata chainAccountsList
    ) external pure returns (BuilderResult memory) {
        ChainAccounts[] memory transferChainAccounts = filterChainAccounts(assetSymbol, chainAccountsList);
        ChainAccounts[] memory paymentChainAccounts;
        if (payment.isToken) {
            paymentChainAccounts = filterChainAccounts(payment.currency, chainAccountsList);
        }

        // INSUFFICIENT_FUNDS
        // There are not enough aggregate funds on all chains to fulfill the transfer.
        {
            uint256 aggregateTransferAssetBalance;
            for (uint256 i = 0; i < transferChainAccounts.length; ++i) {
                aggregateTransferAssetBalance += sumBalances(findAssetPositions(assetSymbol, transferChainAccounts[i].assetPositionsList));
            }
            if (aggregateTransferAssetBalance < amount) {
                revert InsufficientFunds();
            }
        }

        // TODO: Pay with bridged payment.currency?
        // MAX_COST_TOO_HIGH
        // There is at least one chain that does not have sufficient payment assets to cover the maxCost for that chain.
        // Note: This check assumes we will not be bridging payment tokens for the user
        if (payment.isToken) {
            for (uint i = 0; i < payment.maxCosts.length; ++i) {
                uint256 paymentAssetBalanceOnChain = sumBalances(
                    findAssetPositions(
                        assetSymbol,
                        findChainAccounts(payment.maxCosts[i].chainId, paymentChainAccounts)
                            .assetPositionsList
                    )
                );
                uint256 paymentAssetNeeded = payment.maxCosts[i].amount;
                // If the payment token is the transfer token and this is the target chain, we need to account for the transfer amount when checking token balances
                if (Strings.stringEqIgnoreCase(payment.currency, assetSymbol) && chainId == payment.maxCosts[i].chainId) {
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
        {
            uint256 aggregateTransferAssetAvailableBalance;
            for (uint i = 0; i < transferChainAccounts.length; ++i) {
                for (uint j = 0; j < transferChainAccounts[i].assetPositionsList[0].accountBalances.length; ++j) {
                    if (BridgeRoutes.hasBridge(transferChainAccounts[i].chainId, chainId, assetSymbol)) {
                        aggregateTransferAssetAvailableBalance += transferChainAccounts[i].assetPositionsList[0].accountBalances[j].balance;
                    }
                }
            }
            if (aggregateTransferAssetAvailableBalance < amount) {
                revert FundsUnavailable();
            }
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
        uint256 localBalance = sumBalances(findChainAccounts(chainId, transferChainAccounts).assetPositionsList[0]);
        // Note: User will always have enough payment token on destination chain, since we already check that in the MaxCostTooHigh() check
        if (localBalance < amount) {
            // Construct bridge operation if not enough funds on target chain
            // TODO: bridge routing logic (which bridge to prioritize, how many bridges?)

            // TODO: construct action contexts
            if (payment.isToken) {
                // wrap around paycall
            } else {
                bytes[] memory scriptSources = new bytes[](1);
                scriptSources[0] = type(CCTPBridgeActions).creationCode;
                // FIXME
                address scriptAddress = address(0);
                /*
                getCodeAddress(
                    address(0), // IQuarkWallet(accountBalances[i].account).factory().codeJar()
                    type(CCTPBridgeActions).creationCode
                );
                */
                bridgeQuarkOperation = IQuarkWallet.QuarkOperation({
                    nonce: 0, // TODO: get next nonce
                    scriptAddress: scriptAddress,
                    scriptCalldata: abi.encodeWithSelector(
                        CCTPBridgeActions.bridgeUSDC.selector,
                        recipient,
                        amount
                    ),
                    scriptSources: scriptSources,
                    expiry: 99999999999 // TODO: never expire?
                });
            }
        }

        // Then, transfer `amount` of `chainAsset` to `recipient`
        IQuarkWallet.QuarkOperation memory transferQuarkOperation;
        // TODO: construct action contexts
        if (Strings.stringEqIgnoreCase(assetSymbol, "ETH")) {
            if (payment.isToken) {
                // wrap around paycall
            } else {
                // Native ETH transfer
                transferQuarkOperation = ERC20Transfer(chainId, recipient, amount, paymentChainAccounts[0], address(0));
            }
        } else {
            if (payment.isToken) {
                // wrap around paycall
            } else {
                // ERC20 transfer
                transferQuarkOperation = ERC20Transfer(chainId, recipient, amount, paymentChainAccounts[0], address(0));
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
            multiQuarkOperationDigest: new bytes(0),
            quarkOperationDigest: new bytes(0),
            paymentCurrency: payment.currency
        });
    }

    function ERC20Transfer(
        uint256 dstChainId,
        address recipient,
        uint256 amount,
        ChainAccounts memory transferOriginAccount,
        address sender
    ) internal pure returns (IQuarkWallet.QuarkOperation memory) {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(TransferActions).creationCode;
        // uint256 chainId = transferOriginAccount.chainId;
        AssetPositions memory transferAssetPositions = transferOriginAccount.assetPositionsList[0];

        QuarkState memory accountState;
        for (uint256 i = 0; i < transferOriginAccount.quarkStates.length; ++i) {
            if (transferOriginAccount.quarkStates[i].account == sender) {
                accountState = transferOriginAccount.quarkStates[i];
                break;
            }
        }

        // ERC20 transfer
        return IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: getCodeAddress(transferOriginAccount.chainId, type(CCTPBridgeActions).creationCode),
            scriptCalldata: abi.encodeWithSelector(
                TransferActions.transferERC20Token.selector,
                transferAssetPositions.asset,
                recipient,
                amount
            ),
            scriptSources: scriptSources,
            expiry: 99999999999 // TODO: never expire?
        });
    }
}


// 1. Input validation (custom errors)
// 2. Constructing the operation
//   a) Bridge operation (conditional)
//   b) Wrap around Paycall/Quotecall (conditional)
//   c) Transfer operation (non-conditional)
// 3. Constructing the BuilderResult (action contexts, eip-712 digest)
