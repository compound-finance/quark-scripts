// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";

import {Actions} from "./Actions.sol";
import {Accounts} from "./Accounts.sol";
import {BridgeRoutes} from "./BridgeRoutes.sol";
import {EIP712Helper} from "./EIP712Helper.sol";
import {Math} from "src/lib/Math.sol";
import {MorphoInfo} from "./MorphoInfo.sol";
import {Strings} from "./Strings.sol";
import {PaycallWrapper} from "./PaycallWrapper.sol";
import {QuotecallWrapper} from "./QuotecallWrapper.sol";
import {PaymentInfo} from "./PaymentInfo.sol";
import {TokenWrapper} from "./TokenWrapper.sol";
import {QuarkOperationHelper} from "./QuarkOperationHelper.sol";
import {List} from "./List.sol";
import {QuarkBuilderBase} from "./QuarkBuilderBase.sol";

contract QuarkBuilder is QuarkBuilderBase {
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

    /* ===== Main Implementation ===== */

    struct CometRepayIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        uint256 chainId;
        uint256[] collateralAmounts;
        string[] collateralAssetSymbols;
        address comet;
        address repayer;
    }

    function cometRepay(
        CometRepayIntent memory repayIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory /* builderResult */ ) {
        if (repayIntent.collateralAmounts.length != repayIntent.collateralAssetSymbols.length) {
            revert InvalidInput();
        }

        // XXX confirm that the user is not withdrawing beyond their limits

        bool isMaxRepay = repayIntent.amount == type(uint256).max;
        bool useQuotecall = false; // never use Quotecall

        uint256 repayAmount;
        if (isMaxRepay) {
            repayAmount =
                cometRepayMaxAmount(chainAccountsList, repayIntent.chainId, repayIntent.comet, repayIntent.repayer);
        } else {
            repayAmount = repayIntent.amount;
        }

        (IQuarkWallet.QuarkOperation memory repayQuarkOperation, Actions.Action memory repayAction) = Actions.cometRepay(
            Actions.CometRepayInput({
                chainAccountsList: chainAccountsList,
                assetSymbol: repayIntent.assetSymbol,
                amount: repayIntent.amount,
                chainId: repayIntent.chainId,
                collateralAmounts: repayIntent.collateralAmounts,
                collateralAssetSymbols: repayIntent.collateralAssetSymbols,
                comet: repayIntent.comet,
                blockTimestamp: repayIntent.blockTimestamp,
                repayer: repayIntent.repayer
            }),
            payment
        );

        uint256[] memory amountOuts = new uint256[](1);
        amountOuts[0] = repayAmount;
        string[] memory assetSymbolOuts = new string[](1);
        assetSymbolOuts[0] = repayIntent.assetSymbol;
        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: repayIntent.repayer,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                amountIns: repayIntent.collateralAmounts,
                assetSymbolIns: repayIntent.collateralAssetSymbols,
                blockTimestamp: repayIntent.blockTimestamp,
                chainId: repayIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: repayQuarkOperation,
            action: repayAction,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct CometBorrowIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        address borrower;
        uint256 chainId;
        uint256[] collateralAmounts;
        string[] collateralAssetSymbols;
        address comet;
    }

    function cometBorrow(
        CometBorrowIntent memory borrowIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory /* builderResult */ ) {
        if (borrowIntent.collateralAmounts.length != borrowIntent.collateralAssetSymbols.length) {
            revert InvalidInput();
        }

        bool useQuotecall = false; // never use Quotecall

        (IQuarkWallet.QuarkOperation memory borrowQuarkOperation, Actions.Action memory borrowAction) = Actions
            .cometBorrow(
            Actions.CometBorrowInput({
                chainAccountsList: chainAccountsList,
                amount: borrowIntent.amount,
                assetSymbol: borrowIntent.assetSymbol,
                blockTimestamp: borrowIntent.blockTimestamp,
                borrower: borrowIntent.borrower,
                chainId: borrowIntent.chainId,
                collateralAmounts: borrowIntent.collateralAmounts,
                collateralAssetSymbols: borrowIntent.collateralAssetSymbols,
                comet: borrowIntent.comet
            }),
            payment
        );

        uint256[] memory amountIns = new uint256[](1);
        amountIns[0] = borrowIntent.amount;
        string[] memory assetSymbolIns = new string[](1);
        assetSymbolIns[0] = borrowIntent.assetSymbol;

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: borrowIntent.borrower,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: borrowIntent.collateralAmounts,
                assetSymbolOuts: borrowIntent.collateralAssetSymbols,
                blockTimestamp: borrowIntent.blockTimestamp,
                chainId: borrowIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: borrowQuarkOperation,
            action: borrowAction,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct CometSupplyIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        uint256 chainId;
        address comet;
        address sender;
    }

    function cometSupply(
        CometSupplyIntent memory cometSupplyIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory /* builderResult */ ) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        // Initialize comet supply max flag
        bool isMaxSupply = cometSupplyIntent.amount == type(uint256).max;
        // Convert cometSupplyIntent to user aggregated balance
        if (isMaxSupply) {
            cometSupplyIntent.amount =
                Accounts.totalAvailableAsset(cometSupplyIntent.assetSymbol, chainAccountsList, payment);
        }

        (IQuarkWallet.QuarkOperation memory supplyQuarkOperation, Actions.Action memory supplyAction) = Actions
            .cometSupplyAsset(
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

        uint256[] memory amountOuts = new uint256[](1);
        amountOuts[0] = cometSupplyIntent.amount;
        string[] memory assetSymbolOuts = new string[](1);
        assetSymbolOuts[0] = cometSupplyIntent.assetSymbol;
        uint256[] memory amountIns = new uint256[](0);
        string[] memory assetSymbolIns = new string[](0);

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: cometSupplyIntent.sender,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: cometSupplyIntent.blockTimestamp,
                chainId: cometSupplyIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: supplyQuarkOperation,
            action: supplyAction,
            useQuotecall: isMaxSupply
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct CometWithdrawIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        uint256 chainId;
        address comet;
        address withdrawer;
    }

    function cometWithdraw(
        CometWithdrawIntent memory cometWithdrawIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory) {
        // XXX confirm that you actually have the amount to withdraw
        bool isMaxWithdraw = cometWithdrawIntent.amount == type(uint256).max;
        bool useQuotecall = false; // never use Quotecall

        uint256 actualWithdrawAmount = cometWithdrawIntent.amount;
        if (isMaxWithdraw) {
            actualWithdrawAmount = 0;
            // When doing a maxWithdraw will need to find the actual amount instead of uint256 max
            Accounts.CometPositions memory cometPositions =
                Accounts.findCometPositions(cometWithdrawIntent.chainId, cometWithdrawIntent.comet, chainAccountsList);

            for (uint256 i = 0; i < cometPositions.basePosition.accounts.length; ++i) {
                if (cometPositions.basePosition.accounts[i] == cometWithdrawIntent.withdrawer) {
                    actualWithdrawAmount += cometPositions.basePosition.supplied[i];
                }
            }
        }

        (IQuarkWallet.QuarkOperation memory cometWithdrawQuarkOperation, Actions.Action memory cometWithdrawAction) =
        Actions.cometWithdrawAsset(
            Actions.CometWithdraw({
                chainAccountsList: chainAccountsList,
                assetSymbol: cometWithdrawIntent.assetSymbol,
                amount: cometWithdrawIntent.amount,
                chainId: cometWithdrawIntent.chainId,
                comet: cometWithdrawIntent.comet,
                withdrawer: cometWithdrawIntent.withdrawer,
                blockTimestamp: cometWithdrawIntent.blockTimestamp
            }),
            payment
        );

        uint256[] memory amountIns = new uint256[](1);
        amountIns[0] = actualWithdrawAmount;
        string[] memory assetSymbolIns = new string[](1);
        assetSymbolIns[0] = cometWithdrawIntent.assetSymbol;
        uint256[] memory amountOuts = new uint256[](0);
        string[] memory assetSymbolOuts = new string[](0);

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: cometWithdrawIntent.withdrawer,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: cometWithdrawIntent.blockTimestamp,
                chainId: cometWithdrawIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: cometWithdrawQuarkOperation,
            action: cometWithdrawAction,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
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
        // TransferMax will always use quotecall to avoid leaving dust in wallet
        bool useQuotecall = isMaxTransfer;

        // Convert transferIntent to user aggregated balance
        if (isMaxTransfer) {
            transferIntent.amount = Accounts.totalAvailableAsset(transferIntent.assetSymbol, chainAccountsList, payment);
        }

        // Then, transfer `amount` of `assetSymbol` to `recipient`
        (IQuarkWallet.QuarkOperation memory operation, Actions.Action memory action) = Actions.transferAsset(
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

        uint256[] memory amountOuts = new uint256[](1);
        amountOuts[0] = transferIntent.amount;
        string[] memory assetSymbolOuts = new string[](1);
        assetSymbolOuts[0] = transferIntent.assetSymbol;
        uint256[] memory amountIns = new uint256[](0);
        string[] memory assetSymbolIns = new string[](0);

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: transferIntent.sender,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: transferIntent.blockTimestamp,
                chainId: transferIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: operation,
            action: action,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct ZeroExSwapIntent {
        uint256 chainId;
        address entryPoint;
        bytes swapData;
        address sellToken;
        uint256 sellAmount;
        address buyToken;
        uint256 buyAmount;
        address feeToken;
        uint256 feeAmount;
        address sender;
        bool isExactOut;
        uint256 blockTimestamp;
    }

    function swap(
        ZeroExSwapIntent memory swapIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        string memory sellAssetSymbol =
            Accounts.findAssetPositions(swapIntent.sellToken, swapIntent.chainId, chainAccountsList).symbol;
        string memory buyAssetSymbol =
            Accounts.findAssetPositions(swapIntent.buyToken, swapIntent.chainId, chainAccountsList).symbol;
        string memory feeAssetSymbol =
            Accounts.findAssetPositions(swapIntent.feeToken, swapIntent.chainId, chainAccountsList).symbol;

        // Initialize swap max flag (when sell amount is max)
        bool isMaxSwap = swapIntent.sellAmount == type(uint256).max;
        // Convert swapIntent to user aggregated balance
        if (isMaxSwap) {
            swapIntent.sellAmount = Accounts.totalAvailableAsset(sellAssetSymbol, chainAccountsList, payment);
        }

        bool useQuotecall = isMaxSwap;

        // Then, swap `amount` of `assetSymbol` to `recipient`
        (IQuarkWallet.QuarkOperation memory operation, Actions.Action memory action) = Actions.zeroExSwap(
            Actions.ZeroExSwap({
                chainAccountsList: chainAccountsList,
                entryPoint: swapIntent.entryPoint,
                swapData: swapIntent.swapData,
                sellToken: swapIntent.sellToken,
                sellAssetSymbol: sellAssetSymbol,
                sellAmount: swapIntent.sellAmount,
                buyToken: swapIntent.buyToken,
                buyAssetSymbol: buyAssetSymbol,
                buyAmount: swapIntent.buyAmount,
                feeToken: swapIntent.feeToken,
                feeAssetSymbol: feeAssetSymbol,
                feeAmount: swapIntent.feeAmount,
                chainId: swapIntent.chainId,
                sender: swapIntent.sender,
                isExactOut: swapIntent.isExactOut,
                blockTimestamp: swapIntent.blockTimestamp
            }),
            payment,
            useQuotecall
        );

        uint256[] memory amountOuts = new uint256[](1);
        amountOuts[0] = swapIntent.sellAmount;
        string[] memory assetSymbolOuts = new string[](1);
        assetSymbolOuts[0] = sellAssetSymbol;
        uint256[] memory amountIns = new uint256[](1);
        amountIns[0] = swapIntent.buyAmount;
        string[] memory assetSymbolIns = new string[](1);
        assetSymbolIns[0] = buyAssetSymbol;

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: swapIntent.sender,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: swapIntent.blockTimestamp,
                chainId: swapIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: operation,
            action: action,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct RecurringSwapIntent {
        uint256 chainId;
        address sellToken;
        // For exact out swaps, this will be an estimate of the expected input token amount for the first swap
        uint256 sellAmount;
        address buyToken;
        uint256 buyAmount;
        bool isExactOut;
        bytes path;
        uint256 interval;
        address sender;
        uint256 blockTimestamp;
    }

    // Note: We don't currently bridge the input token or the payment token for recurring swaps. Recurring swaps
    // are actions tied to assets on a single chain.
    function recurringSwap(
        RecurringSwapIntent memory swapIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        string memory sellAssetSymbol =
            Accounts.findAssetPositions(swapIntent.sellToken, swapIntent.chainId, chainAccountsList).symbol;
        string memory buyAssetSymbol =
            Accounts.findAssetPositions(swapIntent.buyToken, swapIntent.chainId, chainAccountsList).symbol;

        // Check there are enough of the input token on the target chain
        if (needsBridgedFunds(sellAssetSymbol, swapIntent.sellAmount, swapIntent.chainId, chainAccountsList, payment)) {
            uint256 balanceOnChain = getBalanceOnChain(sellAssetSymbol, swapIntent.chainId, chainAccountsList, payment);
            uint256 amountNeededOnChain =
                getAmountNeededOnChain(sellAssetSymbol, swapIntent.sellAmount, swapIntent.chainId, payment);
            uint256 maxCostOnChain = payment.isToken ? PaymentInfo.findMaxCost(payment, swapIntent.chainId) : 0;
            uint256 availableAssetBalance = balanceOnChain >= maxCostOnChain ? balanceOnChain - maxCostOnChain : 0;
            revert FundsUnavailable(sellAssetSymbol, amountNeededOnChain, availableAssetBalance);
        }

        // Check there are enough of the payment token on the target chain
        if (payment.isToken) {
            uint256 maxCostOnChain = PaymentInfo.findMaxCost(payment, swapIntent.chainId);
            if (needsBridgedFunds(payment.currency, maxCostOnChain, swapIntent.chainId, chainAccountsList, payment)) {
                uint256 balanceOnChain =
                    getBalanceOnChain(payment.currency, swapIntent.chainId, chainAccountsList, payment);
                revert FundsUnavailable(payment.currency, maxCostOnChain, balanceOnChain);
            }
        }

        // We don't support max swap for recurring swaps, so quote call is never used
        bool useQuotecall = false;
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        // TODO: Handle wrapping/unwrapping once the new Quark is out. That will allow us to construct a replayable
        // Multicall transaction that contains 1) the wrapping/unwrapping action and 2) the recurring swap. The wrapping
        // action will need to be smart: for exact in, it will check that balance < sellAmount before wrapping. For exact out,
        // it will always wrap all.
        // // Auto-wrap/unwrap
        // checkAndInsertWrapOrUnwrapAction(
        //     actions,
        //     quarkOperations,
        //     chainAccountsList,
        //     payment,
        //     sellAssetSymbol,
        //     // TODO: We will need to set this to type(uint256).max if isExactOut is true
        //     swapIntent.sellAmount,
        //     swapIntent.chainId,
        //     swapIntent.sender,
        //     swapIntent.blockTimestamp,
        //     useQuotecall
        // );

        // Then, set up the recurring swap operation
        (IQuarkWallet.QuarkOperation memory operation, Actions.Action memory action) = Actions.recurringSwap(
            Actions.RecurringSwapParams({
                chainAccountsList: chainAccountsList,
                sellToken: swapIntent.sellToken,
                sellAssetSymbol: sellAssetSymbol,
                sellAmount: swapIntent.sellAmount,
                buyToken: swapIntent.buyToken,
                buyAssetSymbol: buyAssetSymbol,
                buyAmount: swapIntent.buyAmount,
                isExactOut: swapIntent.isExactOut,
                path: swapIntent.path,
                interval: swapIntent.interval,
                chainId: swapIntent.chainId,
                sender: swapIntent.sender,
                blockTimestamp: swapIntent.blockTimestamp
            }),
            payment,
            useQuotecall
        );
        List.addAction(actions, action);
        List.addQuarkOperation(quarkOperations, operation);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);
        // Validate generated actions for affordability
        if (payment.isToken) {
            assertSufficientPaymentTokenBalances(actionsArray, chainAccountsList, swapIntent.chainId, swapIntent.sender);
        }

        // Merge operations that are from the same chain into one Multicall operation
        (quarkOperationsArray, actionsArray) =
            QuarkOperationHelper.mergeSameChainOperations(quarkOperationsArray, actionsArray);

        // Wrap operations around Paycall/Quotecall if payment is with token
        if (payment.isToken) {
            quarkOperationsArray = QuarkOperationHelper.wrapOperationsWithTokenPayment(
                quarkOperationsArray, actionsArray, payment, useQuotecall
            );
        }

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct MorphoBorrowIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        address borrower;
        uint256 chainId;
        uint256 collateralAmount;
        string collateralAssetSymbol;
    }

    function morphoBorrow(
        MorphoBorrowIntent memory borrowIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory) {
        bool useQuotecall = false; // never use Quotecall

        (IQuarkWallet.QuarkOperation memory borrowQuarkOperation, Actions.Action memory borrowAction) = Actions
            .morphoBorrow(
            Actions.MorphoBorrow({
                chainAccountsList: chainAccountsList,
                assetSymbol: borrowIntent.assetSymbol,
                amount: borrowIntent.amount,
                chainId: borrowIntent.chainId,
                borrower: borrowIntent.borrower,
                blockTimestamp: borrowIntent.blockTimestamp,
                collateralAmount: borrowIntent.collateralAmount,
                collateralAssetSymbol: borrowIntent.collateralAssetSymbol
            }),
            payment
        );

        uint256[] memory amountOuts = new uint256[](1);
        amountOuts[0] = borrowIntent.amount;
        string[] memory assetSymbolOuts = new string[](1);
        assetSymbolOuts[0] = borrowIntent.assetSymbol;
        uint256[] memory amountIns = new uint256[](1);
        amountIns[0] = borrowIntent.collateralAmount;
        string[] memory assetSymbolIns = new string[](1);
        assetSymbolIns[0] = borrowIntent.collateralAssetSymbol;

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: borrowIntent.borrower,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: borrowIntent.blockTimestamp,
                chainId: borrowIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: borrowQuarkOperation,
            action: borrowAction,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct MorphoRepayIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        address repayer;
        uint256 chainId;
        uint256 collateralAmount;
        string collateralAssetSymbol;
    }

    function morphoRepay(
        MorphoRepayIntent memory repayIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory) {
        bool isMaxRepay = repayIntent.amount == type(uint256).max;
        bool useQuotecall = false; // never use Quotecall

        // Only use repayAmount for purpose of bridging, will still use uint256 max for MorphoScript
        uint256 repayAmount = repayIntent.amount;
        if (isMaxRepay) {
            repayAmount = morphoRepayMaxAmount(
                chainAccountsList,
                repayIntent.chainId,
                Accounts.findAssetPositions(repayIntent.assetSymbol, repayIntent.chainId, chainAccountsList).asset,
                Accounts.findAssetPositions(repayIntent.collateralAssetSymbol, repayIntent.chainId, chainAccountsList)
                    .asset,
                repayIntent.repayer
            );
        }

        (IQuarkWallet.QuarkOperation memory repayQuarkOperations, Actions.Action memory repayActions) = Actions
            .morphoRepay(
            Actions.MorphoRepay({
                chainAccountsList: chainAccountsList,
                assetSymbol: repayIntent.assetSymbol,
                amount: repayIntent.amount,
                chainId: repayIntent.chainId,
                repayer: repayIntent.repayer,
                blockTimestamp: repayIntent.blockTimestamp,
                collateralAmount: repayIntent.collateralAmount,
                collateralAssetSymbol: repayIntent.collateralAssetSymbol
            }),
            payment
        );

        uint256[] memory amountOuts = new uint256[](1);
        amountOuts[0] = repayAmount;
        string[] memory assetSymbolOuts = new string[](1);
        assetSymbolOuts[0] = repayIntent.assetSymbol;
        uint256[] memory amountIns = new uint256[](1);
        amountIns[0] = repayIntent.collateralAmount;
        string[] memory assetSymbolIns = new string[](1);
        assetSymbolIns[0] = repayIntent.collateralAssetSymbol;

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: repayIntent.repayer,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: repayIntent.blockTimestamp,
                chainId: repayIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: repayQuarkOperations,
            action: repayActions,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct MorphoVaultSupplyIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        address sender;
        uint256 chainId;
    }

    function morphoVaultSupply(
        MorphoVaultSupplyIntent memory supplyIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory) {
        // If the action is paid for with tokens, filter out any chain accounts that do not have corresponding payment information
        if (payment.isToken) {
            chainAccountsList = Accounts.findChainAccountsWithPaymentInfo(chainAccountsList, payment);
        }

        // Initialize supply max flag
        bool isMaxSupply = supplyIntent.amount == type(uint256).max;
        bool useQuotecall = isMaxSupply;
        // Convert supplyIntent to user aggregated balance
        if (isMaxSupply) {
            supplyIntent.amount = Accounts.totalAvailableAsset(supplyIntent.assetSymbol, chainAccountsList, payment);
        }

        (IQuarkWallet.QuarkOperation memory supplyQuarkOperation, Actions.Action memory supplyAction) = Actions
            .morphoVaultSupply(
            Actions.MorphoVaultSupply({
                chainAccountsList: chainAccountsList,
                assetSymbol: supplyIntent.assetSymbol,
                amount: supplyIntent.amount,
                blockTimestamp: supplyIntent.blockTimestamp,
                chainId: supplyIntent.chainId,
                sender: supplyIntent.sender
            }),
            payment,
            useQuotecall
        );

        uint256[] memory amountOuts = new uint256[](1);
        amountOuts[0] = supplyIntent.amount;
        string[] memory assetSymbolOuts = new string[](1);
        assetSymbolOuts[0] = supplyIntent.assetSymbol;
        uint256[] memory amountIns = new uint256[](0);
        string[] memory assetSymbolIns = new string[](0);

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: supplyIntent.sender,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: supplyIntent.blockTimestamp,
                chainId: supplyIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: supplyQuarkOperation,
            action: supplyAction,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    struct MorphoVaultWithdrawIntent {
        uint256 amount;
        string assetSymbol;
        uint256 blockTimestamp;
        uint256 chainId;
        address withdrawer;
    }

    function morphoVaultWithdraw(
        MorphoVaultWithdrawIntent memory withdrawIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external pure returns (BuilderResult memory) {
        // XXX confirm that you actually have the amount to withdraw

        bool isMaxWithdraw = withdrawIntent.amount == type(uint256).max;
        bool useQuotecall = false; // never use Quotecall

        (IQuarkWallet.QuarkOperation memory cometWithdrawQuarkOperation, Actions.Action memory cometWithdrawAction) =
        Actions.morphoVaultWithdraw(
            Actions.MorphoVaultWithdraw({
                chainAccountsList: chainAccountsList,
                assetSymbol: withdrawIntent.assetSymbol,
                amount: withdrawIntent.amount,
                blockTimestamp: withdrawIntent.blockTimestamp,
                chainId: withdrawIntent.chainId,
                withdrawer: withdrawIntent.withdrawer
            }),
            payment
        );

        uint256[] memory amountIns = new uint256[](1);
        amountIns[0] = withdrawIntent.amount;
        string[] memory assetSymbolIns = new string[](1);
        assetSymbolIns[0] = withdrawIntent.assetSymbol;
        uint256[] memory amountOuts = new uint256[](0);
        string[] memory assetSymbolOuts = new string[](0);

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: QuarkBuilderBase.ActionIntent({
                actor: withdrawIntent.withdrawer,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: withdrawIntent.blockTimestamp,
                chainId: withdrawIntent.chainId
            }),
            chainAccountsList: chainAccountsList,
            payment: payment,
            quarkOperation: cometWithdrawQuarkOperation,
            action: cometWithdrawAction,
            useQuotecall: useQuotecall
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }

    // TODO: Commenting because it is currently unused and will result in stack too deep
    // Note: The root case for the stack too deep is the yul optimizer. The optimizer currently
    // inlines the internal call to `Actions.morphoClaimRewards`. Compiling using `via-ir` but
    // without the optimizer works.

    // struct MorphoRewardsClaimIntent {
    //     uint256 blockTimestamp;
    //     address claimer;
    //     uint256 chainId;
    //     address[] accounts;
    //     uint256[] claimables;
    //     address[] distributors;
    //     address[] rewards;
    //     bytes32[][] proofs;
    // }

    // function morphoClaimRewards(
    //     MorphoRewardsClaimIntent memory claimIntent,
    //     Accounts.ChainAccounts[] memory chainAccountsList,
    //     PaymentInfo.Payment memory payment
    // ) external pure returns (BuilderResult memory) {
    //     if (
    //         claimIntent.accounts.length != claimIntent.claimables.length
    //             || claimIntent.accounts.length != claimIntent.distributors.length
    //             || claimIntent.accounts.length != claimIntent.rewards.length
    //             || claimIntent.accounts.length != claimIntent.proofs.length
    //     ) {
    //         revert InvalidInput();
    //     }

    //     bool useQuotecall = false; // never use Quotecall
    //     List.DynamicArray memory actions = List.newList();
    //     List.DynamicArray memory quarkOperations = List.newList();

    //     // when paying with tokens, you may need to bridge the payment token to cover the cost
    //     if (payment.isToken) {
    //         uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, claimIntent.chainId);
    //         // if you're claiming rewards in payment token, you can use the withdrawn amount to cover the cost
    //         for (uint256 i = 0; i < claimIntent.rewards.length; ++i) {
    //             if (
    //                 Strings.stringEqIgnoreCase(
    //                     payment.currency,
    //                     Accounts.findAssetPositions(claimIntent.rewards[i], claimIntent.chainId, chainAccountsList)
    //                         .symbol
    //                 )
    //             ) {
    //                 maxCostOnDstChain = Math.subtractFlooredAtZero(maxCostOnDstChain, claimIntent.claimables[i]);
    //             }
    //         }

    //         if (needsBridgedFunds(payment.currency, maxCostOnDstChain, claimIntent.chainId, chainAccountsList, payment))
    //         {
    //             (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
    //             Actions.constructBridgeOperations(
    //                 Actions.BridgeOperationInfo({
    //                     assetSymbol: payment.currency,
    //                     amountNeededOnDst: maxCostOnDstChain,
    //                     dstChainId: claimIntent.chainId,
    //                     recipient: claimIntent.claimer,
    //                     blockTimestamp: claimIntent.blockTimestamp,
    //                     useQuotecall: useQuotecall
    //                 }),
    //                 chainAccountsList,
    //                 payment
    //             );

    //             for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
    //                 List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
    //                 List.addAction(actions, bridgeActions[i]);
    //             }
    //         }
    //     }

    //     (IQuarkWallet.QuarkOperation memory cometWithdrawQuarkOperation, Actions.Action memory cometWithdrawAction) =
    //     Actions.morphoClaimRewards(
    //         Actions.MorphoClaimRewards({
    //             chainAccountsList: chainAccountsList,
    //             accounts: claimIntent.accounts,
    //             blockTimestamp: claimIntent.blockTimestamp,
    //             chainId: claimIntent.chainId,
    //             claimables: claimIntent.claimables,
    //             claimer: claimIntent.claimer,
    //             distributors: claimIntent.distributors,
    //             rewards: claimIntent.rewards,
    //             proofs: claimIntent.proofs
    //         }),
    //         payment
    //     );
    //     List.addAction(actions, cometWithdrawAction);
    //     List.addQuarkOperation(quarkOperations, cometWithdrawQuarkOperation);

    //     // Convert actions and quark operations to arrays
    //     Actions.Action[] memory actionsArray = List.toActionArray(actions);
    //     IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

    //     // Validate generated actions for affordability
    //     if (payment.isToken) {
    //         uint256 supplementalPaymentTokenBalance = 0;
    //         for (uint256 i = 0; i < claimIntent.rewards.length; ++i) {
    //             if (
    //                 Strings.stringEqIgnoreCase(
    //                     payment.currency,
    //                     Accounts.findAssetPositions(claimIntent.rewards[i], claimIntent.chainId, chainAccountsList)
    //                         .symbol
    //                 )
    //             ) {
    //                 supplementalPaymentTokenBalance += claimIntent.claimables[i];
    //             }
    //         }

    //         assertSufficientPaymentTokenBalances(
    //             PaymentBalanceAssertionArgs({
    //                 actions: actionsArray,
    //                 chainAccountsList: chainAccountsList,
    //                 targetChainId: claimIntent.chainId,
    //                 account: claimIntent.claimer,
    //                 supplementalPaymentTokenBalance: supplementalPaymentTokenBalance
    //             })
    //         );
    //     }

    //     // Merge operations that are from the same chain into one Multicall operation
    //     (quarkOperationsArray, actionsArray) =
    //         QuarkOperationHelper.mergeSameChainOperations(quarkOperationsArray, actionsArray);

    //     // Wrap operations around Paycall/Quotecall if payment is with token
    //     if (payment.isToken) {
    //         quarkOperationsArray = QuarkOperationHelper.wrapOperationsWithTokenPayment(
    //             quarkOperationsArray, actionsArray, payment, useQuotecall
    //         );
    //     }

    //     return BuilderResult({
    //         version: VERSION,
    //         actions: actionsArray,
    //         quarkOperations: quarkOperationsArray,
    //         paymentCurrency: payment.currency,
    //         eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
    //     });
    // }
}
