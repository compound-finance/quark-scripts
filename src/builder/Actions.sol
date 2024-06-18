// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {CCTP} from "./BridgeRoutes.sol";
import {Strings} from "./Strings.sol";
import {Accounts} from "./Accounts.sol";
import {CodeJarHelper} from "./CodeJarHelper.sol";

import {TransferActions} from "../DeFiScripts.sol";

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {PaycallWrapper} from "./PaycallWrapper.sol";
import {PaymentInfo} from "./PaymentInfo.sol";

library Actions {
    /* ===== Constants ===== */
    string constant PAYMENT_METHOD_OFFCHAIN = "OFFCHAIN";
    string constant PAYMENT_METHOD_PAYCALL = "PAY_CALL";
    string constant PAYMENT_METHOD_QUOTECALL = "QUOTE_CALL";

    string constant ACTION_TYPE_BRIDGE = "BRIDGE";
    string constant ACTION_TYPE_TRANSFER = "TRANSFER";

    string constant BRIDGE_TYPE_CCTP = "CCTP";

    uint256 constant TRANSFER_EXPIRY_BUFFER = 7 days;
    uint256 constant BRIDGE_EXPIRY_BUFFER = 7 days;

    /* ===== Custom Errors ===== */

    error BridgingUnsupportedForAsset();
    error InvalidAssetForBridge();

    /* ===== Input Types ===== */

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
        string bridgeType;
    }

    function bridgeAsset(BridgeAsset memory bridge, PaymentInfo.Payment memory payment)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        if (Strings.stringEqIgnoreCase(bridge.assetSymbol, "USDC")) {
            return bridgeUSDC(bridge, payment);
        } else {
            revert BridgingUnsupportedForAsset();
        }
    }

    function bridgeUSDC(BridgeAsset memory bridge, PaymentInfo.Payment memory payment)
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
            quarkOperation = PaycallWrapper.wrap(
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
        Action memory action = Actions.Action({
            chainId: bridge.srcChainId,
            quarkAccount: bridge.sender,
            actionType: ACTION_TYPE_BRIDGE,
            actionContext: abi.encode(bridgeActionContext),
            paymentMethod: payment.isToken ? PAYMENT_METHOD_PAYCALL : PAYMENT_METHOD_OFFCHAIN,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, bridge.srcChainId).token : address(0),
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, bridge.srcChainId) : 0
        });

        return (quarkOperation, action);
    }

    // TODO: Handle paycall

    function transferAsset(TransferAsset memory transfer, PaymentInfo.Payment memory payment)
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
            quarkOperation = PaycallWrapper.wrap(
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
        Action memory action = Actions.Action({
            chainId: transfer.chainId,
            quarkAccount: transfer.sender,
            actionType: ACTION_TYPE_TRANSFER,
            actionContext: abi.encode(transferActionContext),
            paymentMethod: payment.isToken ? PAYMENT_METHOD_PAYCALL : PAYMENT_METHOD_OFFCHAIN,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, transfer.chainId).token : address(0),
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, transfer.chainId) : 0
        });

        return (quarkOperation, action);
    }
}
