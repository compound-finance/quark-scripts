// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {CCTP} from "./BridgeRoutes.sol";
import {Strings} from "./Strings.sol";
import {Accounts} from "./Accounts.sol";
import {CodeJarHelper} from "./CodeJarHelper.sol";

import {CometSupplyActions, TransferActions} from "../DeFiScripts.sol";

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {PaycallWrapper} from "./PaycallWrapper.sol";
import {QuotecallWrapper} from "./QuotecallWrapper.sol";
import {PaymentInfo} from "./PaymentInfo.sol";

library Actions {
    /* ===== Constants ===== */
    string constant PAYMENT_METHOD_OFFCHAIN = "OFFCHAIN";
    string constant PAYMENT_METHOD_PAYCALL = "PAY_CALL";
    string constant PAYMENT_METHOD_QUOTECALL = "QUOTE_CALL";

    string constant ACTION_TYPE_BORROW = "BORROW";
    string constant ACTION_TYPE_BRIDGE = "BRIDGE";
    string constant ACTION_TYPE_BUY = "BUY";
    string constant ACTION_TYPE_CLAIM_REWARDS = "CLAIM_REWARDS";
    string constant ACTION_TYPE_DRIP_TOKENS = "DRIP_TOKENS";
    string constant ACTION_TYPE_REPAY = "REPAY";
    string constant ACTION_TYPE_SELL = "SELL";
    string constant ACTION_TYPE_SUPPLY = "SUPPLY";
    string constant ACTION_TYPE_TRANSFER = "TRANSFER";
    string constant ACTION_TYPE_WITHDRAW = "WITHDRAW";
    string constant ACTION_TYPE_WITHDRAW_AND_BORROW = "WITHDRAW_AND_BORROW";

    string constant BRIDGE_TYPE_CCTP = "CCTP";

    /* expiry buffers */
    uint256 constant STANDARD_EXPIRY_BUFFER = 7 days;

    uint256 constant BRIDGE_EXPIRY_BUFFER = 7 days;
    uint256 constant TRANSFER_EXPIRY_BUFFER = 7 days;

    /* ===== Custom Errors ===== */

    error BridgingUnsupportedForAsset();
    error InvalidAssetForBridge();

    /* ===== Input Types ===== */

    struct CometSupply {
        Accounts.ChainAccounts[] chainAccountsList;
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        uint256 chainId;
        address comet;
        address sender;
    }

    struct TransferAsset {
        Accounts.ChainAccounts[] chainAccountsList;
        string assetSymbol;
        uint256 amount;
        uint256 chainId;
        address sender;
        address recipient;
        uint256 blockTimestamp;
    }

    struct BridgeAsset {
        Accounts.ChainAccounts[] chainAccountsList;
        string assetSymbol;
        uint256 amount;
        uint256 srcChainId;
        address sender;
        uint256 destinationChainId;
        address recipient;
        uint256 blockTimestamp;
    }

    /* ===== Output Types ===== */

    // With Action, we try to define fields that are as 1:1 as possible with
    // the simulate endpoint request schema.
    struct Action {
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

    struct BorrowActionContext {
        uint256 amount;
        uint256 chainId;
        uint256[] collateralAmounts;
        uint256[] collateralTokenPrices;
        address[] collateralTokens;
        address comet;
        uint256 price;
        address token;
    }

    struct BridgeActionContext {
        uint256 amount;
        string bridgeType;
        uint256 chainId;
        uint256 destinationChainId;
        uint256 price;
        address recipient;
        address token;
    }

    struct BuyActionContext {
        uint256 amount;
        uint256 chainId;
        uint256 price;
        address token;
    }

    struct ClaimRewardsActionContext {
        uint256 amount;
        uint256 chainId;
        uint256 price;
        address token;
    }

    struct DripTokensActionContext {
        uint256 chainId;
    }

    struct RepayActionContext {
        uint256 amount;
        uint256 chainId;
        uint256[] collateralAmounts;
        uint256[] collateralTokenPrices;
        address[] collateralTokens;
        address comet;
        uint256 price;
        address token;
    }

    struct SellActionContext {
        uint256 amount;
        uint256 chainId;
        uint256 price;
        address token;
    }

    struct SupplyActionContext {
        uint256 amount;
        uint256 chainId;
        address comet;
        uint256 price;
        address token;
    }

    struct TransferActionContext {
        uint256 amount;
        uint256 chainId;
        uint256 price;
        address recipient;
        address token;
    }

    struct WithdrawActionContext {
        uint256 chainId;
        uint256 amount;
        address comet;
        uint256 price;
    }

    struct WithdrawAndBorrowActionContext {
        uint256 borrowAmount;
        uint256 chainId;
        uint256[] collateralAmounts;
        uint256[] collateralTokenPrices;
        address[] collateralTokens;
        address comet;
        uint256 price;
        address token;
        uint256 withdrawAmount;
    }

    function bridgeAsset(BridgeAsset memory bridge, PaymentInfo.Payment memory payment, bool useQuoteCall)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        if (Strings.stringEqIgnoreCase(bridge.assetSymbol, "USDC")) {
            return bridgeUSDC(bridge, payment, useQuoteCall);
        } else {
            revert BridgingUnsupportedForAsset();
        }
    }

    function bridgeUSDC(BridgeAsset memory bridge, PaymentInfo.Payment memory payment, bool useQuoteCall)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        if (!Strings.stringEqIgnoreCase(bridge.assetSymbol, "USDC")) {
            revert InvalidAssetForBridge();
        }

        Accounts.ChainAccounts memory srcChainAccounts =
            Accounts.findChainAccounts(bridge.srcChainId, bridge.chainAccountsList);

        Accounts.AssetPositions memory srcUSDCPositions =
            Accounts.findAssetPositions("USDC", srcChainAccounts.assetPositionsList);

        Accounts.QuarkState memory accountState = Accounts.findQuarkState(bridge.sender, srcChainAccounts.quarkStates);

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = CCTP.bridgeScriptSource();

        // Construct QuarkOperation
        IQuarkWallet.QuarkOperation memory quarkOperation = IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: CodeJarHelper.getCodeAddress(scriptSources[0]),
            scriptCalldata: CCTP.encodeBridgeUSDC(
                bridge.srcChainId, bridge.destinationChainId, bridge.amount, bridge.recipient, srcUSDCPositions.asset
                ),
            scriptSources: scriptSources,
            expiry: bridge.blockTimestamp + BRIDGE_EXPIRY_BUFFER
        });

        if (payment.isToken) {
            // Wrap operation with paycall
            quarkOperation = useQuoteCall
                ? QuotecallWrapper.wrap(
                    quarkOperation, bridge.srcChainId, payment.currency, PaymentInfo.findMaxCost(payment, bridge.srcChainId)
                )
                : PaycallWrapper.wrap(
                    quarkOperation, bridge.srcChainId, payment.currency, PaymentInfo.findMaxCost(payment, bridge.srcChainId)
                );
        }

        // Construct Action
        BridgeActionContext memory bridgeActionContext = BridgeActionContext({
            amount: bridge.amount,
            price: srcUSDCPositions.usdPrice,
            token: srcUSDCPositions.asset,
            chainId: bridge.srcChainId,
            recipient: bridge.recipient,
            destinationChainId: bridge.destinationChainId,
            bridgeType: BRIDGE_TYPE_CCTP
        });

        string memory paymentMethod;
        if (payment.isToken) {
            // To pay with token, it has to be a paycall or quotecall.
            paymentMethod = useQuoteCall ? PAYMENT_METHOD_QUOTECALL : PAYMENT_METHOD_PAYCALL;
        } else {
            paymentMethod = PAYMENT_METHOD_OFFCHAIN;
        }

        Action memory action = Actions.Action({
            chainId: bridge.srcChainId,
            quarkAccount: bridge.sender,
            actionType: ACTION_TYPE_BRIDGE,
            actionContext: abi.encode(bridgeActionContext),
            paymentMethod: paymentMethod,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, bridge.srcChainId).token : address(0),
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, bridge.srcChainId) : 0
        });

        return (quarkOperation, action);
    }

    function cometSupplyAsset(CometSupply memory cometSupply, PaymentInfo.Payment memory payment)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(CometSupplyActions).creationCode;

        Accounts.ChainAccounts memory accounts =
            Accounts.findChainAccounts(cometSupply.chainId, cometSupply.chainAccountsList);

        Accounts.AssetPositions memory assetPositions =
            Accounts.findAssetPositions(cometSupply.assetSymbol, accounts.assetPositionsList);

        Accounts.QuarkState memory accountState = Accounts.findQuarkState(cometSupply.sender, accounts.quarkStates);

        bytes memory scriptCalldata;
        if (Strings.stringEqIgnoreCase(cometSupply.assetSymbol, "ETH")) {
            // XXX handle wrapping ETH
        } else {
            scriptCalldata = abi.encodeWithSelector(
                CometSupplyActions.supply.selector, cometSupply.comet, assetPositions.asset, cometSupply.amount
            );
        }
        // Construct QuarkOperation
        IQuarkWallet.QuarkOperation memory quarkOperation = IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: CodeJarHelper.getCodeAddress(type(CometSupplyActions).creationCode),
            scriptCalldata: scriptCalldata,
            scriptSources: scriptSources,
            expiry: cometSupply.blockTimestamp + STANDARD_EXPIRY_BUFFER
        });

        if (payment.isToken) {
            // Wrap operation with paycall
            quarkOperation = PaycallWrapper.wrap(
                quarkOperation,
                cometSupply.chainId,
                payment.currency,
                PaymentInfo.findMaxCost(payment, cometSupply.chainId)
            );
        }

        // Construct Action
        CometSupplyActionContext memory cometSupplyActionContext = CometSupplyActionContext({
            amount: cometSupply.amount,
            chainId: cometSupply.chainId,
            comet: cometSupply.comet,
            price: assetPositions.usdPrice,
            token: assetPositions.asset
        });
        Action memory action = Actions.Action({
            chainId: cometSupply.chainId,
            quarkAccount: cometSupply.sender,
            actionType: ACTION_TYPE_COMET_SUPPLY,
            actionContext: abi.encode(cometSupplyActionContext),
            paymentMethod: payment.isToken ? PAYMENT_METHOD_PAYCALL : PAYMENT_METHOD_OFFCHAIN,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, cometSupply.chainId).token : address(0),
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, cometSupply.chainId) : 0
        });

        return (quarkOperation, action);
    }

    function transferAsset(TransferAsset memory transfer, PaymentInfo.Payment memory payment, bool useQuoteCall)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(TransferActions).creationCode;

        Accounts.ChainAccounts memory accounts =
            Accounts.findChainAccounts(transfer.chainId, transfer.chainAccountsList);

        Accounts.AssetPositions memory assetPositions =
            Accounts.findAssetPositions(transfer.assetSymbol, accounts.assetPositionsList);

        Accounts.QuarkState memory accountState = Accounts.findQuarkState(transfer.sender, accounts.quarkStates);

        bytes memory scriptCalldata;
        if (Strings.stringEqIgnoreCase(transfer.assetSymbol, "ETH")) {
            // Native token transfer
            scriptCalldata = abi.encodeWithSelector(
                TransferActions.transferNativeToken.selector, transfer.recipient, transfer.amount
            );
        } else {
            // ERC20 transfer
            scriptCalldata = abi.encodeWithSelector(
                TransferActions.transferERC20Token.selector, assetPositions.asset, transfer.recipient, transfer.amount
            );
        }
        // Construct QuarkOperation
        IQuarkWallet.QuarkOperation memory quarkOperation = IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: CodeJarHelper.getCodeAddress(type(TransferActions).creationCode),
            scriptCalldata: scriptCalldata,
            scriptSources: scriptSources,
            expiry: transfer.blockTimestamp + TRANSFER_EXPIRY_BUFFER
        });

        if (payment.isToken) {
            // Wrap operation with paycall
            quarkOperation = useQuoteCall
                ? QuotecallWrapper.wrap(
                    quarkOperation, transfer.chainId, payment.currency, PaymentInfo.findMaxCost(payment, transfer.chainId)
                )
                : PaycallWrapper.wrap(
                    quarkOperation, transfer.chainId, payment.currency, PaymentInfo.findMaxCost(payment, transfer.chainId)
                );
        }

        // Construct Action
        TransferActionContext memory transferActionContext = TransferActionContext({
            amount: transfer.amount,
            price: assetPositions.usdPrice,
            token: assetPositions.asset,
            chainId: transfer.chainId,
            recipient: transfer.recipient
        });
        string memory paymentMethod;
        if (payment.isToken) {
            // To pay with token, it has to be a paycall or quotecall.
            paymentMethod = useQuoteCall ? PAYMENT_METHOD_QUOTECALL : PAYMENT_METHOD_PAYCALL;
        } else {
            paymentMethod = PAYMENT_METHOD_OFFCHAIN;
        }

        Action memory action = Actions.Action({
            chainId: transfer.chainId,
            quarkAccount: transfer.sender,
            actionType: ACTION_TYPE_TRANSFER,
            actionContext: abi.encode(transferActionContext),
            paymentMethod: paymentMethod,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, transfer.chainId).token : address(0),
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, transfer.chainId) : 0
        });

        return (quarkOperation, action);
    }

    function findActionsOfType(Actions.Action[] memory actions, string memory actionType)
        internal
        pure
        returns (Actions.Action[] memory)
    {
        uint256 count = 0;
        Actions.Action[] memory result = new Actions.Action[](actions.length);
        for (uint256 i = 0; i < actions.length; ++i) {
            if (Strings.stringEqIgnoreCase(actions[i].actionType, actionType)) {
                result[count++] = actions[i];
            }
        }

        return truncate(result, count);
    }

    function findActionsNotOfType(Actions.Action[] memory actions, string memory actionType)
        internal
        pure
        returns (Actions.Action[] memory)
    {
        uint256 count = 0;
        Actions.Action[] memory result = new Actions.Action[](actions.length);
        for (uint256 i = 0; i < actions.length; ++i) {
            if (!Strings.stringEqIgnoreCase(actions[i].actionType, actionType)) {
                result[count++] = actions[i];
            }
        }

        return truncate(result, count);
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

    // These structs are mostly used internally and returned in serialized format as bytes: actionContext
    // The caller can then decode them back into their struct form.
    // These empty husk functions exist so that the structs make it into the abi so the clients can know how to decode them.
    function emptyTransferActionContext() external pure returns (TransferActionContext memory) {
        TransferActionContext[] memory ts = new TransferActionContext[](1);
        return ts[0];
    }

    function emptyBridgeActionContext() external pure returns (BridgeActionContext memory) {
        BridgeActionContext[] memory bs = new BridgeActionContext[](1);
        return bs[0];
    }
}
