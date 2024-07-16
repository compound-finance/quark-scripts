// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {BridgeRoutes, CCTP} from "./BridgeRoutes.sol";
import {Strings} from "./Strings.sol";
import {Accounts} from "./Accounts.sol";
import {CodeJarHelper} from "./CodeJarHelper.sol";

import {
    ApproveAndSwap,
    CometRepayAndWithdrawMultipleAssets,
    CometSupplyActions,
    CometSupplyMultipleAssetsAndBorrow,
    CometWithdrawActions,
    TransferActions
} from "../DeFiScripts.sol";
import {WrapperActions} from "../WrapperScripts.sol";

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {PaymentInfo} from "./PaymentInfo.sol";
import {TokenWrapper} from "./TokenWrapper.sol";
import {List} from "./List.sol";

library Actions {
    /* ===== Constants ===== */
    string constant PAYMENT_METHOD_OFFCHAIN = "OFFCHAIN";
    string constant PAYMENT_METHOD_PAYCALL = "PAY_CALL";
    string constant PAYMENT_METHOD_QUOTECALL = "QUOTE_CALL";

    string constant ACTION_TYPE_BORROW = "BORROW";
    string constant ACTION_TYPE_BRIDGE = "BRIDGE";
    string constant ACTION_TYPE_CLAIM_REWARDS = "CLAIM_REWARDS";
    string constant ACTION_TYPE_DRIP_TOKENS = "DRIP_TOKENS";
    string constant ACTION_TYPE_REPAY = "REPAY";
    string constant ACTION_TYPE_SUPPLY = "SUPPLY";
    string constant ACTION_TYPE_SWAP = "SWAP";
    string constant ACTION_TYPE_TRANSFER = "TRANSFER";
    string constant ACTION_TYPE_WITHDRAW = "WITHDRAW";
    string constant ACTION_TYPE_WITHDRAW_AND_BORROW = "WITHDRAW_AND_BORROW";
    string constant ACTION_TYPE_WRAP = "WRAP";
    string constant ACTION_TYPE_UNWRAP = "UNWRAP";

    string constant BRIDGE_TYPE_CCTP = "CCTP";

    /* expiry buffers */
    uint256 constant STANDARD_EXPIRY_BUFFER = 7 days;

    uint256 constant BRIDGE_EXPIRY_BUFFER = 7 days;
    uint256 constant SWAP_EXPIRY_BUFFER = 3 days;
    uint256 constant TRANSFER_EXPIRY_BUFFER = 7 days;

    /* ===== Custom Errors ===== */

    error BridgingUnsupportedForAsset();
    error InvalidAssetForBridge();
    error InvalidAssetForWrappingAction();
    error NotEnoughFundsToBridge(string assetSymbol, uint256 requiredAmount, uint256 amountLeftToBridge);

    /* ===== Input Types ===== */

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

    struct CometSupply {
        Accounts.ChainAccounts[] chainAccountsList;
        string assetSymbol;
        uint256 amount;
        uint256 chainId;
        address comet;
        address sender;
        uint256 blockTimestamp;
    }

    struct CometWithdraw {
        Accounts.ChainAccounts[] chainAccountsList;
        string assetSymbol;
        uint256 amount;
        uint256 chainId;
        address comet;
        address withdrawer;
        uint256 blockTimestamp;
    }

    struct WrapOrUnwrapAsset {
        Accounts.ChainAccounts[] chainAccountsList;
        string assetSymbol;
        uint256 amount;
        uint256 chainId;
        address sender;
        uint256 blockTimestamp;
    }

    struct ZeroExSwap {
        Accounts.ChainAccounts[] chainAccountsList;
        address entryPoint;
        bytes swapData;
        address sellToken;
        string sellAssetSymbol;
        uint256 sellAmount;
        address buyToken;
        string buyAssetSymbol;
        uint256 expectedBuyAmount;
        address feeToken;
        string feeAssetSymbol;
        uint256 feeAmount;
        uint256 chainId;
        address sender;
        uint256 blockTimestamp;
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

    // Note: Mainly to avoid stack too deep errors
    struct BridgeOperationInfo {
        string assetSymbol;
        uint256 amountNeededOnDst;
        uint256 dstChainId;
        address recipient;
        uint256 blockTimestamp;
        bool useQuotecall;
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
        string paymentTokenSymbol;
        uint256 paymentMaxCost;
    }

    struct BorrowActionContext {
        uint256 amount;
        string assetSymbol;
        uint256 chainId;
        uint256[] collateralAmounts;
        string[] collateralAssetSymbols;
        uint256[] collateralTokenPrices;
        address[] collateralTokens;
        address comet;
        uint256 price;
        address token;
    }

    struct BridgeActionContext {
        uint256 amount;
        string assetSymbol;
        string bridgeType;
        uint256 chainId;
        uint256 destinationChainId;
        uint256 price;
        address recipient;
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
        string assetSymbol;
        uint256 chainId;
        uint256[] collateralAmounts;
        string[] collateralAssetSymbols;
        uint256[] collateralTokenPrices;
        address[] collateralTokens;
        address comet;
        uint256 price;
        address token;
    }

    struct SupplyActionContext {
        uint256 amount;
        string assetSymbol;
        uint256 chainId;
        address comet;
        uint256 price;
        address token;
    }

    struct SwapActionContext {
        uint256 chainId;
        uint256 feeAmount;
        string feeAssetSymbol;
        address feeToken;
        uint256 feeTokenPrice;
        uint256 inputAmount;
        string inputAssetSymbol;
        address inputToken;
        uint256 inputTokenPrice;
        // Note: The output amount should be inclusive of the feeAmount
        uint256 outputAmount;
        string outputAssetSymbol;
        address outputToken;
        uint256 outputTokenPrice;
    }

    struct TransferActionContext {
        uint256 amount;
        string assetSymbol;
        uint256 chainId;
        uint256 price;
        address recipient;
        address token;
    }

    struct WithdrawActionContext {
        uint256 amount;
        string assetSymbol;
        uint256 chainId;
        address comet;
        uint256 price;
        address token;
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

    struct WrapOrUnwrapActionContext {
        uint256 chainId;
        uint256 amount;
        address token;
        string fromAssetSymbol;
        string toAssetSymbol;
    }

    function constructBridgeOperations(
        BridgeOperationInfo memory bridgeInfo,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure returns (IQuarkWallet.QuarkOperation[] memory, Action[] memory) {
        /*
         * at most one bridge operation per non-destination chain,
         * and at most one transferIntent operation on the destination chain.
         *
         * therefore the upper bound is chainAccountsList.length.
         */
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        // Note: Assumes that the asset uses the same # of decimals on each chain
        uint256 balanceOnDstChain =
            Accounts.getBalanceOnChain(bridgeInfo.assetSymbol, bridgeInfo.dstChainId, chainAccountsList);
        uint256 amountLeftToBridge = bridgeInfo.amountNeededOnDst - balanceOnDstChain;

        // Check to see if there are counterpart tokens on the destination chain that can be used. If there are, subtract the balance from `amountLeftToBridge`
        if (TokenWrapper.hasWrapperContract(bridgeInfo.dstChainId, bridgeInfo.assetSymbol)) {
            string memory counterpartSymbol =
                TokenWrapper.getWrapperCounterpartSymbol(bridgeInfo.dstChainId, bridgeInfo.assetSymbol);
            uint256 counterpartBalanceOnDstChain =
                Accounts.getBalanceOnChain(counterpartSymbol, bridgeInfo.dstChainId, chainAccountsList);
            uint256 counterpartTokenAmountToUse;
            // In case if the counterpart token is the payment token, we need to leave enough payment token on the source chain to cover the payment max cost
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, counterpartSymbol)) {
                if (
                    counterpartBalanceOnDstChain
                        >= amountLeftToBridge + PaymentInfo.findMaxCost(payment, bridgeInfo.dstChainId)
                ) {
                    counterpartTokenAmountToUse = amountLeftToBridge;
                } else {
                    // NOTE: This logic only works when the user has only a single account on each chain. If there are multiple,
                    // then we need to re-adjust this.
                    counterpartTokenAmountToUse =
                        counterpartBalanceOnDstChain - PaymentInfo.findMaxCost(payment, bridgeInfo.dstChainId);
                }
            } else {
                if (counterpartBalanceOnDstChain >= amountLeftToBridge) {
                    counterpartTokenAmountToUse = amountLeftToBridge;
                } else {
                    counterpartTokenAmountToUse = counterpartBalanceOnDstChain;
                }
            }

            // NOTE: Only adjusts amount LeftToBridge
            // The real wrapping/unwrapping will be done outside of the construct bridge operation function
            // Update amountLeftToBridge
            amountLeftToBridge -= counterpartTokenAmountToUse;
        }

        uint256 bridgeActionCount = 0;
        // TODO: bridge routing logic (which bridge to prioritize, how many bridges?)
        // Iterate chainAccountList and find chains that can provide enough funds to bridge.
        // One optimization is to allow the client to provide optimal routes.
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            // End loop if enough tokens have been bridged
            if (amountLeftToBridge == 0) {
                break;
            }

            Accounts.ChainAccounts memory srcChainAccounts = chainAccountsList[i];
            // Skip if the current chain is the target chain, since bridging is not possible
            if (srcChainAccounts.chainId == bridgeInfo.dstChainId) {
                continue;
            }

            // Skip if there is no bridge route for the current chain to the target chain
            if (!BridgeRoutes.canBridge(srcChainAccounts.chainId, bridgeInfo.dstChainId, bridgeInfo.assetSymbol)) {
                continue;
            }

            Accounts.AssetPositions memory srcAssetPositions =
                Accounts.findAssetPositions(bridgeInfo.assetSymbol, srcChainAccounts.assetPositionsList);
            Accounts.AccountBalance[] memory srcAccountBalances = srcAssetPositions.accountBalances;
            // TODO: Make logic smarter. Currently, this uses a greedy algorithm.
            // e.g. Optimize by trying to bridge with the least amount of bridge operations
            for (uint256 j = 0; j < srcAccountBalances.length; ++j) {
                uint256 amountToBridge;
                // If the intent token is the payment token, we need to leave enough payment token on the source chain to cover the payment max cost
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, bridgeInfo.assetSymbol)) {
                    if (
                        srcAccountBalances[j].balance
                            >= amountLeftToBridge + PaymentInfo.findMaxCost(payment, srcChainAccounts.chainId)
                    ) {
                        amountToBridge = amountLeftToBridge;
                    } else {
                        // NOTE: This logic only works when the user has only a single account on each chain. If there are multiple,
                        // then we need to re-adjust this.
                        amountToBridge =
                            srcAccountBalances[j].balance - PaymentInfo.findMaxCost(payment, srcChainAccounts.chainId);
                    }
                } else {
                    if (srcAccountBalances[j].balance >= amountLeftToBridge) {
                        amountToBridge = amountLeftToBridge;
                    } else {
                        amountToBridge = srcAccountBalances[j].balance;
                    }
                }

                amountLeftToBridge -= amountToBridge;

                (IQuarkWallet.QuarkOperation memory operation, Actions.Action memory action) = bridgeAsset(
                    BridgeAsset({
                        chainAccountsList: chainAccountsList,
                        assetSymbol: bridgeInfo.assetSymbol,
                        amount: amountToBridge,
                        // where it comes from
                        srcChainId: srcChainAccounts.chainId,
                        sender: srcAccountBalances[j].account,
                        // where it goes
                        destinationChainId: bridgeInfo.dstChainId,
                        recipient: bridgeInfo.recipient,
                        blockTimestamp: bridgeInfo.blockTimestamp
                    }),
                    payment,
                    bridgeInfo.useQuotecall
                );

                List.addAction(actions, action);
                List.addQuarkOperation(quarkOperations, operation);
                bridgeActionCount++;
            }
        }

        if (amountLeftToBridge > 0) {
            revert NotEnoughFundsToBridge(
                bridgeInfo.assetSymbol, bridgeInfo.amountNeededOnDst - balanceOnDstChain, amountLeftToBridge
            );
        }

        // Convert actions and quark operations to arrays
        return (List.toQuarkOperationArray(quarkOperations), List.toActionArray(actions));
    }

    function bridgeAsset(BridgeAsset memory bridge, PaymentInfo.Payment memory payment, bool useQuotecall)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        if (Strings.stringEqIgnoreCase(bridge.assetSymbol, "USDC")) {
            return bridgeUSDC(bridge, payment, useQuotecall);
        } else {
            revert BridgingUnsupportedForAsset();
        }
    }

    function bridgeUSDC(BridgeAsset memory bridge, PaymentInfo.Payment memory payment, bool useQuotecall)
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

        // Construct Action
        BridgeActionContext memory bridgeActionContext = BridgeActionContext({
            amount: bridge.amount,
            price: srcUSDCPositions.usdPrice,
            token: srcUSDCPositions.asset,
            assetSymbol: srcUSDCPositions.symbol,
            chainId: bridge.srcChainId,
            recipient: bridge.recipient,
            destinationChainId: bridge.destinationChainId,
            bridgeType: BRIDGE_TYPE_CCTP
        });

        string memory paymentMethod;
        if (payment.isToken) {
            // To pay with token, it has to be a paycall or quotecall.
            paymentMethod = useQuotecall ? PAYMENT_METHOD_QUOTECALL : PAYMENT_METHOD_PAYCALL;
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
            paymentTokenSymbol: payment.currency,
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, bridge.srcChainId) : 0
        });

        return (quarkOperation, action);
    }

    struct CometBorrowInput {
        Accounts.ChainAccounts[] chainAccountsList;
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        address borrower;
        uint256 chainId;
        uint256[] collateralAmounts;
        string[] collateralAssetSymbols;
        address comet;
    }

    function cometBorrow(CometBorrowInput memory borrowInput, PaymentInfo.Payment memory payment)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(CometSupplyMultipleAssetsAndBorrow).creationCode;

        Accounts.ChainAccounts memory accounts =
            Accounts.findChainAccounts(borrowInput.chainId, borrowInput.chainAccountsList);

        Accounts.QuarkState memory accountState = Accounts.findQuarkState(borrowInput.borrower, accounts.quarkStates);

        Accounts.AssetPositions memory borrowAssetPositions =
            Accounts.findAssetPositions(borrowInput.assetSymbol, accounts.assetPositionsList);

        uint256[] memory collateralTokenPrices = new uint256[](borrowInput.collateralAssetSymbols.length);
        address[] memory collateralTokens = new address[](borrowInput.collateralAssetSymbols.length);

        for (uint256 i = 0; i < borrowInput.collateralAssetSymbols.length; ++i) {
            Accounts.AssetPositions memory assetPositions =
                Accounts.findAssetPositions(borrowInput.collateralAssetSymbols[i], accounts.assetPositionsList);
            collateralTokenPrices[i] = assetPositions.usdPrice;
            collateralTokens[i] = assetPositions.asset;
        }

        // XXX handle wrapping ETH?
        bytes memory scriptCalldata = abi.encodeWithSelector(
            CometSupplyMultipleAssetsAndBorrow.run.selector,
            borrowInput.comet,
            collateralTokens,
            borrowInput.collateralAmounts,
            borrowAssetPositions.asset,
            borrowInput.amount
        );

        // Construct QuarkOperation
        IQuarkWallet.QuarkOperation memory quarkOperation = IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: CodeJarHelper.getCodeAddress(type(CometSupplyMultipleAssetsAndBorrow).creationCode),
            scriptCalldata: scriptCalldata,
            scriptSources: scriptSources,
            expiry: borrowInput.blockTimestamp + STANDARD_EXPIRY_BUFFER
        });

        // Construct Action
        BorrowActionContext memory repayActionContext = BorrowActionContext({
            assetSymbol: borrowInput.assetSymbol,
            amount: borrowInput.amount,
            chainId: borrowInput.chainId,
            collateralAmounts: borrowInput.collateralAmounts,
            collateralTokenPrices: collateralTokenPrices,
            collateralTokens: collateralTokens,
            collateralAssetSymbols: borrowInput.collateralAssetSymbols,
            comet: borrowInput.comet,
            price: borrowAssetPositions.usdPrice,
            token: borrowAssetPositions.asset
        });
        Action memory action = Actions.Action({
            chainId: borrowInput.chainId,
            quarkAccount: borrowInput.borrower,
            actionType: ACTION_TYPE_BORROW,
            actionContext: abi.encode(repayActionContext),
            paymentMethod: payment.isToken ? PAYMENT_METHOD_PAYCALL : PAYMENT_METHOD_OFFCHAIN,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, borrowInput.chainId).token : address(0),
            paymentTokenSymbol: payment.currency,
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, borrowInput.chainId) : 0
        });

        return (quarkOperation, action);
    }

    struct CometRepayInput {
        Accounts.ChainAccounts[] chainAccountsList;
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        uint256 chainId;
        uint256[] collateralAmounts;
        string[] collateralAssetSymbols;
        address comet;
        address repayer;
    }

    function cometRepay(CometRepayInput memory repayInput, PaymentInfo.Payment memory payment)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(CometRepayAndWithdrawMultipleAssets).creationCode;

        Accounts.ChainAccounts memory accounts =
            Accounts.findChainAccounts(repayInput.chainId, repayInput.chainAccountsList);

        Accounts.QuarkState memory accountState = Accounts.findQuarkState(repayInput.repayer, accounts.quarkStates);

        Accounts.AssetPositions memory repayAssetPositions =
            Accounts.findAssetPositions(repayInput.assetSymbol, accounts.assetPositionsList);

        uint256[] memory collateralTokenPrices = new uint256[](repayInput.collateralAssetSymbols.length);
        address[] memory collateralTokens = new address[](repayInput.collateralAssetSymbols.length);

        for (uint256 i = 0; i < repayInput.collateralAssetSymbols.length; ++i) {
            Accounts.AssetPositions memory assetPositions =
                Accounts.findAssetPositions(repayInput.collateralAssetSymbols[i], accounts.assetPositionsList);
            collateralTokenPrices[i] = assetPositions.usdPrice;
            collateralTokens[i] = assetPositions.asset;
        }

        // XXX handle wrapping ETH?
        bytes memory scriptCalldata = abi.encodeWithSelector(
            CometRepayAndWithdrawMultipleAssets.run.selector,
            repayInput.comet,
            collateralTokens,
            repayInput.collateralAmounts,
            repayAssetPositions.asset,
            repayInput.amount
        );

        // Construct QuarkOperation
        IQuarkWallet.QuarkOperation memory quarkOperation = IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: CodeJarHelper.getCodeAddress(type(CometRepayAndWithdrawMultipleAssets).creationCode),
            scriptCalldata: scriptCalldata,
            scriptSources: scriptSources,
            expiry: repayInput.blockTimestamp + STANDARD_EXPIRY_BUFFER
        });

        // Construct Action
        RepayActionContext memory repayActionContext = RepayActionContext({
            amount: repayInput.amount,
            assetSymbol: repayInput.assetSymbol,
            chainId: repayInput.chainId,
            collateralAmounts: repayInput.collateralAmounts,
            collateralAssetSymbols: repayInput.collateralAssetSymbols,
            collateralTokenPrices: collateralTokenPrices,
            collateralTokens: collateralTokens,
            comet: repayInput.comet,
            price: repayAssetPositions.usdPrice,
            token: repayAssetPositions.asset
        });
        Action memory action = Actions.Action({
            chainId: repayInput.chainId,
            quarkAccount: repayInput.repayer,
            actionType: ACTION_TYPE_REPAY,
            actionContext: abi.encode(repayActionContext),
            paymentMethod: payment.isToken ? PAYMENT_METHOD_PAYCALL : PAYMENT_METHOD_OFFCHAIN,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, repayInput.chainId).token : address(0),
            paymentTokenSymbol: payment.currency,
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, repayInput.chainId) : 0
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

        // Construct Action
        SupplyActionContext memory cometSupplyActionContext = SupplyActionContext({
            amount: cometSupply.amount,
            chainId: cometSupply.chainId,
            comet: cometSupply.comet,
            price: assetPositions.usdPrice,
            token: assetPositions.asset,
            assetSymbol: assetPositions.symbol
        });
        Action memory action = Actions.Action({
            chainId: cometSupply.chainId,
            quarkAccount: cometSupply.sender,
            actionType: ACTION_TYPE_SUPPLY,
            actionContext: abi.encode(cometSupplyActionContext),
            paymentMethod: payment.isToken ? PAYMENT_METHOD_PAYCALL : PAYMENT_METHOD_OFFCHAIN,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, cometSupply.chainId).token : address(0),
            paymentTokenSymbol: payment.currency,
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, cometSupply.chainId) : 0
        });

        return (quarkOperation, action);
    }

    function cometWithdrawAsset(
        CometWithdraw memory cometWithdraw,
        PaymentInfo.Payment memory payment,
        bool useQuotecall
    ) internal pure returns (IQuarkWallet.QuarkOperation memory, Action memory) {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(CometWithdrawActions).creationCode;

        Accounts.ChainAccounts memory accounts =
            Accounts.findChainAccounts(cometWithdraw.chainId, cometWithdraw.chainAccountsList);

        Accounts.AssetPositions memory assetPositions =
            Accounts.findAssetPositions(cometWithdraw.assetSymbol, accounts.assetPositionsList);

        Accounts.QuarkState memory accountState =
            Accounts.findQuarkState(cometWithdraw.withdrawer, accounts.quarkStates);

        bytes memory scriptCalldata;
        if (Strings.stringEqIgnoreCase(cometWithdraw.assetSymbol, "ETH")) {
            // XXX handle unwrapping ETH
        } else {
            scriptCalldata = abi.encodeWithSelector(
                CometWithdrawActions.withdraw.selector, cometWithdraw.comet, assetPositions.asset, cometWithdraw.amount
            );
        }
        // Construct QuarkOperation
        IQuarkWallet.QuarkOperation memory quarkOperation = IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: CodeJarHelper.getCodeAddress(type(CometWithdrawActions).creationCode),
            scriptCalldata: scriptCalldata,
            scriptSources: scriptSources,
            expiry: cometWithdraw.blockTimestamp + STANDARD_EXPIRY_BUFFER
        });

        // Construct Action
        WithdrawActionContext memory cometWithdrawActionContext = WithdrawActionContext({
            amount: cometWithdraw.amount,
            assetSymbol: cometWithdraw.assetSymbol,
            chainId: cometWithdraw.chainId,
            comet: cometWithdraw.comet,
            price: assetPositions.usdPrice,
            token: assetPositions.asset
        });
        Action memory action = Actions.Action({
            chainId: cometWithdraw.chainId,
            quarkAccount: cometWithdraw.withdrawer,
            actionType: ACTION_TYPE_WITHDRAW,
            actionContext: abi.encode(cometWithdrawActionContext),
            paymentMethod: paymentMethodForPayment(payment, useQuotecall),
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken
                ? PaymentInfo.knownToken(payment.currency, cometWithdraw.chainId).token
                : address(0),
            paymentTokenSymbol: payment.currency,
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, cometWithdraw.chainId) : 0
        });

        return (quarkOperation, action);
    }

    function transferAsset(TransferAsset memory transfer, PaymentInfo.Payment memory payment, bool useQuotecall)
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

        // Construct Action
        TransferActionContext memory transferActionContext = TransferActionContext({
            amount: transfer.amount,
            price: assetPositions.usdPrice,
            token: assetPositions.asset,
            assetSymbol: assetPositions.symbol,
            chainId: transfer.chainId,
            recipient: transfer.recipient
        });

        Action memory action = Actions.Action({
            chainId: transfer.chainId,
            quarkAccount: transfer.sender,
            actionType: ACTION_TYPE_TRANSFER,
            actionContext: abi.encode(transferActionContext),
            paymentMethod: paymentMethodForPayment(payment, useQuotecall),
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, transfer.chainId).token : address(0),
            paymentTokenSymbol: payment.currency,
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, transfer.chainId) : 0
        });

        return (quarkOperation, action);
    }

    function paymentMethodForPayment(PaymentInfo.Payment memory payment, bool useQuotecall)
        internal
        pure
        returns (string memory)
    {
        if (payment.isToken && useQuotecall) {
            return PAYMENT_METHOD_QUOTECALL;
        } else if (payment.isToken && !useQuotecall) {
            return PAYMENT_METHOD_PAYCALL;
        } else {
            return PAYMENT_METHOD_OFFCHAIN;
        }
    }

    function wrapOrUnwrapAsset(
        WrapOrUnwrapAsset memory wrapOrUnwrap,
        PaymentInfo.Payment memory payment,
        bool useQuotecall
    ) internal pure returns (IQuarkWallet.QuarkOperation memory, Action memory) {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(WrapperActions).creationCode;

        Accounts.ChainAccounts memory accounts =
            Accounts.findChainAccounts(wrapOrUnwrap.chainId, wrapOrUnwrap.chainAccountsList);

        Accounts.AssetPositions memory assetPositions =
            Accounts.findAssetPositions(wrapOrUnwrap.assetSymbol, accounts.assetPositionsList);

        Accounts.QuarkState memory accountState = Accounts.findQuarkState(wrapOrUnwrap.sender, accounts.quarkStates);
        // Construct QuarkOperation
        IQuarkWallet.QuarkOperation memory quarkOperation = IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: CodeJarHelper.getCodeAddress(type(WrapperActions).creationCode),
            scriptCalldata: TokenWrapper.encodeActionToWrapOrUnwrap(
                wrapOrUnwrap.chainId, wrapOrUnwrap.assetSymbol, wrapOrUnwrap.amount
                ),
            scriptSources: scriptSources,
            expiry: wrapOrUnwrap.blockTimestamp + STANDARD_EXPIRY_BUFFER
        });

        // Construct Action
        WrapOrUnwrapActionContext memory wrapOrUnwrapActionContext = WrapOrUnwrapActionContext({
            chainId: wrapOrUnwrap.chainId,
            amount: wrapOrUnwrap.amount,
            token: assetPositions.asset,
            fromAssetSymbol: assetPositions.symbol,
            toAssetSymbol: TokenWrapper.getWrapperCounterpartSymbol(wrapOrUnwrap.chainId, assetPositions.symbol)
        });

        string memory paymentMethod;
        if (payment.isToken) {
            // To pay with token, it has to be a paycall or quotecall.
            paymentMethod = useQuotecall ? PAYMENT_METHOD_QUOTECALL : PAYMENT_METHOD_PAYCALL;
        } else {
            paymentMethod = PAYMENT_METHOD_OFFCHAIN;
        }

        Action memory action = Actions.Action({
            chainId: wrapOrUnwrap.chainId,
            quarkAccount: wrapOrUnwrap.sender,
            actionType: TokenWrapper.isWrappedToken(wrapOrUnwrap.chainId, assetPositions.symbol)
                ? ACTION_TYPE_UNWRAP
                : ACTION_TYPE_WRAP,
            actionContext: abi.encode(wrapOrUnwrapActionContext),
            paymentMethod: paymentMethod,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken
                ? PaymentInfo.knownToken(payment.currency, wrapOrUnwrap.chainId).token
                : address(0),
            paymentTokenSymbol: payment.currency,
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, wrapOrUnwrap.chainId) : 0
        });

        return (quarkOperation, action);
    }

    function zeroExSwap(ZeroExSwap memory swap, PaymentInfo.Payment memory payment, bool useQuotecall)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory, Action memory)
    {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(ApproveAndSwap).creationCode;

        Accounts.ChainAccounts memory accounts = Accounts.findChainAccounts(swap.chainId, swap.chainAccountsList);

        Accounts.AssetPositions memory sellTokenAssetPositions =
            Accounts.findAssetPositions(swap.sellAssetSymbol, accounts.assetPositionsList);

        Accounts.AssetPositions memory buyTokenAssetPositions =
            Accounts.findAssetPositions(swap.buyAssetSymbol, accounts.assetPositionsList);

        Accounts.AssetPositions memory feeTokenAssetPositions =
            Accounts.findAssetPositions(swap.feeAssetSymbol, accounts.assetPositionsList);

        Accounts.QuarkState memory accountState = Accounts.findQuarkState(swap.sender, accounts.quarkStates);

        // TODO: Handle wrapping ETH? Do we need to?
        bytes memory scriptCalldata = abi.encodeWithSelector(
            ApproveAndSwap.run.selector,
            swap.entryPoint,
            swap.sellToken,
            swap.sellAmount,
            swap.buyToken,
            swap.expectedBuyAmount,
            swap.swapData
        );

        // Construct QuarkOperation
        IQuarkWallet.QuarkOperation memory quarkOperation = IQuarkWallet.QuarkOperation({
            nonce: accountState.quarkNextNonce,
            scriptAddress: CodeJarHelper.getCodeAddress(type(ApproveAndSwap).creationCode),
            scriptCalldata: scriptCalldata,
            scriptSources: scriptSources,
            expiry: swap.blockTimestamp + SWAP_EXPIRY_BUFFER
        });

        // Construct Action
        SwapActionContext memory swapActionContext = SwapActionContext({
            chainId: swap.chainId,
            feeAmount: swap.feeAmount,
            feeAssetSymbol: swap.feeAssetSymbol,
            feeToken: swap.feeToken,
            feeTokenPrice: feeTokenAssetPositions.usdPrice,
            inputAmount: swap.sellAmount,
            inputAssetSymbol: swap.sellAssetSymbol,
            inputToken: swap.sellToken,
            inputTokenPrice: sellTokenAssetPositions.usdPrice,
            outputAmount: swap.expectedBuyAmount,
            outputAssetSymbol: swap.buyAssetSymbol,
            outputToken: swap.buyToken,
            outputTokenPrice: buyTokenAssetPositions.usdPrice
        });
        string memory paymentMethod;
        if (payment.isToken) {
            // To pay with token, it has to be a paycall or quotecall.
            paymentMethod = useQuotecall ? PAYMENT_METHOD_QUOTECALL : PAYMENT_METHOD_PAYCALL;
        } else {
            paymentMethod = PAYMENT_METHOD_OFFCHAIN;
        }

        Action memory action = Actions.Action({
            chainId: swap.chainId,
            quarkAccount: swap.sender,
            actionType: ACTION_TYPE_SWAP,
            actionContext: abi.encode(swapActionContext),
            paymentMethod: paymentMethod,
            // Null address for OFFCHAIN payment.
            paymentToken: payment.isToken ? PaymentInfo.knownToken(payment.currency, swap.chainId).token : address(0),
            paymentTokenSymbol: payment.currency,
            paymentMaxCost: payment.isToken ? PaymentInfo.findMaxCost(payment, swap.chainId) : 0
        });

        return (quarkOperation, action);
    }

    function findActionsOfType(Action[] memory actions, string memory actionType)
        internal
        pure
        returns (Action[] memory)
    {
        uint256 count = 0;
        Action[] memory result = new Action[](actions.length);
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

    function truncate(Action[] memory actions, uint256 length) internal pure returns (Action[] memory) {
        Action[] memory result = new Action[](length);
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
    function emptyBorrowActionContext() external pure returns (BorrowActionContext memory) {
        BorrowActionContext[] memory bs = new BorrowActionContext[](1);
        return bs[0];
    }

    function emptyBridgeActionContext() external pure returns (BridgeActionContext memory) {
        BridgeActionContext[] memory bs = new BridgeActionContext[](1);
        return bs[0];
    }

    function emptyClaimRewardsActionContext() external pure returns (ClaimRewardsActionContext memory) {
        ClaimRewardsActionContext[] memory cs = new ClaimRewardsActionContext[](1);
        return cs[0];
    }

    function emptyDripTokensActionContext() external pure returns (DripTokensActionContext memory) {
        DripTokensActionContext[] memory ds = new DripTokensActionContext[](1);
        return ds[0];
    }

    function emptyRepayActionContext() external pure returns (RepayActionContext memory) {
        RepayActionContext[] memory rs = new RepayActionContext[](1);
        return rs[0];
    }

    function emptySupplyActionContext() external pure returns (SupplyActionContext memory) {
        SupplyActionContext[] memory ss = new SupplyActionContext[](1);
        return ss[0];
    }

    function emptySwapActionContext() external pure returns (SwapActionContext memory) {
        SwapActionContext[] memory ss = new SwapActionContext[](1);
        return ss[0];
    }

    function emptyTransferActionContext() external pure returns (TransferActionContext memory) {
        TransferActionContext[] memory ts = new TransferActionContext[](1);
        return ts[0];
    }

    function emptyWithdrawActionContext() external pure returns (WithdrawActionContext memory) {
        WithdrawActionContext[] memory ws = new WithdrawActionContext[](1);
        return ws[0];
    }

    function emptyWithdrawAndBorrowActionContext() external pure returns (WithdrawAndBorrowActionContext memory) {
        WithdrawAndBorrowActionContext[] memory ws = new WithdrawAndBorrowActionContext[](1);
        return ws[0];
    }
}
