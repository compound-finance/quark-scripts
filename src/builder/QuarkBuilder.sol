// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

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

contract QuarkBuilder {
    /* ===== Constants ===== */

    string constant VERSION = "0.0.5";

    /* ===== Custom Errors ===== */

    error AssetPositionNotFound();
    error FundsUnavailable(string assetSymbol, uint256 requiredAmount, uint256 actualAmount);
    error InvalidActionChain();
    error InvalidActionType();
    error InvalidInput();
    error MaxCostTooHigh();
    error MissingWrapperCounterpart();
    error InvalidRepayActionContext();

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

    function cometRepayMaxAmount(
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 chainId,
        address comet,
        address repayer
    ) internal pure returns (uint256) {
        uint256 totalBorrowForAccount = Accounts.totalBorrowForAccount(chainAccountsList, chainId, comet, repayer);
        uint256 buffer = totalBorrowForAccount / 1000; // 0.1%
        return totalBorrowForAccount + buffer;
    }

    function morphoRepayMaxAmount(
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 chainId,
        address loanToken,
        address collateralToken,
        address repayer
    ) internal pure returns (uint256 amount) {
        uint256 totalBorrowForAccount =
            Accounts.totalMorphoBorrowForAccount(chainAccountsList, chainId, loanToken, collateralToken, repayer);
        uint256 buffer = totalBorrowForAccount / 1000; // 0.1%
        amount = totalBorrowForAccount + buffer;
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

        assertFundsAvailable(repayIntent.chainId, repayIntent.assetSymbol, repayAmount, chainAccountsList, payment);

        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        if (needsBridgedFunds(repayIntent.assetSymbol, repayAmount, repayIntent.chainId, chainAccountsList, payment)) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = repayAmount;
            // If action is paid for with tokens and the payment token is the
            // repay token, we need to add the max cost to the
            // amountNeededOnDst for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, repayIntent.assetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, repayIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: repayIntent.assetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: repayIntent.chainId,
                    recipient: repayIntent.repayer,
                    blockTimestamp: repayIntent.blockTimestamp,
                    useQuotecall: useQuotecall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                List.addAction(actions, bridgeActions[i]);
                List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
            }
        }

        // Auto-wrap
        checkAndInsertWrapOrUnwrapAction(
            actions,
            quarkOperations,
            chainAccountsList,
            payment,
            repayIntent.assetSymbol,
            repayAmount,
            repayIntent.chainId,
            repayIntent.repayer,
            repayIntent.blockTimestamp,
            useQuotecall
        );

        (IQuarkWallet.QuarkOperation memory repayQuarkOperations, Actions.Action memory repayActions) = Actions
            .cometRepay(
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

        List.addAction(actions, repayActions);
        List.addQuarkOperation(quarkOperations, repayQuarkOperations);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

        // Validate generated actions for affordability
        if (payment.isToken) {
            // if you are withdrawing the payment token, you can pay with the
            // withdrawn funds
            uint256 supplementalPaymentTokenBalance = 0;
            for (uint256 i = 0; i < repayIntent.collateralAssetSymbols.length; ++i) {
                if (Strings.stringEqIgnoreCase(payment.currency, repayIntent.collateralAssetSymbols[i])) {
                    supplementalPaymentTokenBalance += repayIntent.collateralAmounts[i];
                }
            }

            assertSufficientPaymentTokenBalances(
                actionsArray,
                chainAccountsList,
                repayIntent.chainId,
                repayIntent.repayer,
                supplementalPaymentTokenBalance
            );
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

        // max actions length = bridge each collateral asset + bridge payment token + perform borrow action
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        bool useQuotecall = false; // never use Quotecall
        bool paymentTokenIsCollateralAsset = false;

        for (uint256 i = 0; i < borrowIntent.collateralAssetSymbols.length; ++i) {
            string memory assetSymbol = borrowIntent.collateralAssetSymbols[i];
            uint256 supplyAmount = borrowIntent.collateralAmounts[i];

            assertFundsAvailable(borrowIntent.chainId, assetSymbol, supplyAmount, chainAccountsList, payment);

            if (Strings.stringEqIgnoreCase(assetSymbol, payment.currency)) {
                paymentTokenIsCollateralAsset = true;
            }

            if (needsBridgedFunds(assetSymbol, supplyAmount, borrowIntent.chainId, chainAccountsList, payment)) {
                // Note: Assumes that the asset uses the same # of decimals on each chain
                uint256 amountNeededOnDst = supplyAmount;
                // If action is paid for with tokens and the payment token is
                // the supply token, we need to add the max cost to the
                // amountNeededOnDst for target chain
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, assetSymbol)) {
                    amountNeededOnDst += PaymentInfo.findMaxCost(payment, borrowIntent.chainId);
                }
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: assetSymbol,
                        amountNeededOnDst: amountNeededOnDst,
                        dstChainId: borrowIntent.chainId,
                        recipient: borrowIntent.borrower,
                        blockTimestamp: borrowIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 j = 0; j < bridgeQuarkOperations.length; ++j) {
                    List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[j]);
                    List.addAction(actions, bridgeActions[j]);
                }
            }
        }

        // when paying with tokens, you may need to bridge the payment token to cover the cost
        if (payment.isToken && !paymentTokenIsCollateralAsset) {
            uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, borrowIntent.chainId);
            // but if you're borrowing the payment token, you can use the
            // borrowed amount to cover the cost

            if (Strings.stringEqIgnoreCase(payment.currency, borrowIntent.assetSymbol)) {
                maxCostOnDstChain = Math.subtractFlooredAtZero(maxCostOnDstChain, borrowIntent.amount);
            }

            if (
                needsBridgedFunds(payment.currency, maxCostOnDstChain, borrowIntent.chainId, chainAccountsList, payment)
            ) {
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: payment.currency,
                        amountNeededOnDst: maxCostOnDstChain,
                        dstChainId: borrowIntent.chainId,
                        recipient: borrowIntent.borrower,
                        blockTimestamp: borrowIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                    List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
                    List.addAction(actions, bridgeActions[i]);
                }
            }
        }

        // Auto-wrap on collateral supply
        for (uint256 i = 0; i < borrowIntent.collateralAssetSymbols.length; ++i) {
            checkAndInsertWrapOrUnwrapAction(
                actions,
                quarkOperations,
                chainAccountsList,
                payment,
                borrowIntent.collateralAssetSymbols[i],
                borrowIntent.collateralAmounts[i],
                borrowIntent.chainId,
                borrowIntent.borrower,
                borrowIntent.blockTimestamp,
                useQuotecall
            );
        }

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

        List.addQuarkOperation(quarkOperations, borrowQuarkOperation);
        List.addAction(actions, borrowAction);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

        // Validate generated actions for affordability
        if (payment.isToken) {
            uint256 supplementalPaymentTokenBalance = 0;
            if (Strings.stringEqIgnoreCase(payment.currency, borrowIntent.assetSymbol)) {
                supplementalPaymentTokenBalance += borrowIntent.amount;
            }

            assertSufficientPaymentTokenBalances(
                actionsArray,
                chainAccountsList,
                borrowIntent.chainId,
                borrowIntent.borrower,
                supplementalPaymentTokenBalance
            );
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

        assertFundsAvailable(
            cometSupplyIntent.chainId,
            cometSupplyIntent.assetSymbol,
            cometSupplyIntent.amount,
            chainAccountsList,
            payment
        );

        bool useQuotecall = isMaxSupply;
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        if (
            needsBridgedFunds(
                cometSupplyIntent.assetSymbol,
                cometSupplyIntent.amount,
                cometSupplyIntent.chainId,
                chainAccountsList,
                payment
            )
        ) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = cometSupplyIntent.amount;
            // If action is paid for with tokens and the payment token is the
            // transfer token, we need to add the max cost to the
            // amountNeededOnDst for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, cometSupplyIntent.assetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, cometSupplyIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: cometSupplyIntent.assetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: cometSupplyIntent.chainId,
                    recipient: cometSupplyIntent.sender,
                    blockTimestamp: cometSupplyIntent.blockTimestamp,
                    useQuotecall: useQuotecall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                List.addAction(actions, bridgeActions[i]);
                List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
            }
        }

        // Auto-wrap
        checkAndInsertWrapOrUnwrapAction(
            actions,
            quarkOperations,
            chainAccountsList,
            payment,
            cometSupplyIntent.assetSymbol,
            cometSupplyIntent.amount,
            cometSupplyIntent.chainId,
            cometSupplyIntent.sender,
            cometSupplyIntent.blockTimestamp,
            useQuotecall
        );

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

        List.addQuarkOperation(quarkOperations, supplyQuarkOperation);
        List.addAction(actions, supplyAction);

        // TODO: Bridge payment token
        // Convert actions and quark operations to array
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

        // Validate generated actions for affordability
        if (payment.isToken) {
            assertSufficientPaymentTokenBalances(
                actionsArray, chainAccountsList, cometSupplyIntent.chainId, cometSupplyIntent.sender
            );
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
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        // when paying with tokens, you may need to bridge the payment token to cover the cost
        if (payment.isToken) {
            uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, cometWithdrawIntent.chainId);
            // if you're withdrawing the payment token, you can use the withdrawn amount to cover the cost
            if (Strings.stringEqIgnoreCase(payment.currency, cometWithdrawIntent.assetSymbol)) {
                // XXX in the withdrawMax case, use the Comet balance
                maxCostOnDstChain = Math.subtractFlooredAtZero(maxCostOnDstChain, cometWithdrawIntent.amount);
            }

            if (
                needsBridgedFunds(
                    payment.currency, maxCostOnDstChain, cometWithdrawIntent.chainId, chainAccountsList, payment
                )
            ) {
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: payment.currency,
                        amountNeededOnDst: maxCostOnDstChain,
                        dstChainId: cometWithdrawIntent.chainId,
                        recipient: cometWithdrawIntent.withdrawer,
                        blockTimestamp: cometWithdrawIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                    List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
                    List.addAction(actions, bridgeActions[i]);
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
        List.addAction(actions, cometWithdrawAction);
        List.addQuarkOperation(quarkOperations, cometWithdrawQuarkOperation);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

        // Validate generated actions for affordability
        if (payment.isToken) {
            uint256 supplementalPaymentTokenBalance = 0;
            if (Strings.stringEqIgnoreCase(payment.currency, cometWithdrawIntent.assetSymbol)) {
                if (isMaxWithdraw) {
                    // when doing a maxWithdraw of the payment token, add the account's supplied balance
                    // as supplemental payment token balance
                    //
                    // assumes that a maxWithdraw is for the base asset, since
                    // you cannot maxWithdraw Collateral
                    Accounts.CometPositions memory cometPositions = Accounts.findCometPositions(
                        cometWithdrawIntent.chainId, cometWithdrawIntent.comet, chainAccountsList
                    );

                    for (uint256 i = 0; i < cometPositions.basePosition.accounts.length; ++i) {
                        if (cometPositions.basePosition.accounts[i] == cometWithdrawIntent.withdrawer) {
                            supplementalPaymentTokenBalance += cometPositions.basePosition.supplied[i];
                        }
                    }
                } else {
                    supplementalPaymentTokenBalance += cometWithdrawIntent.amount;
                }
            }

            assertSufficientPaymentTokenBalances(
                actionsArray,
                chainAccountsList,
                cometWithdrawIntent.chainId,
                cometWithdrawIntent.withdrawer,
                supplementalPaymentTokenBalance
            );
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
        // Convert transferIntent to user aggregated balance
        if (isMaxTransfer) {
            transferIntent.amount = Accounts.totalAvailableAsset(transferIntent.assetSymbol, chainAccountsList, payment);
        }

        assertFundsAvailable(
            transferIntent.chainId, transferIntent.assetSymbol, transferIntent.amount, chainAccountsList, payment
        );

        // TransferMax will always use quotecall to avoid leaving dust in wallet
        bool useQuotecall = isMaxTransfer;
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();
        if (
            needsBridgedFunds(
                transferIntent.assetSymbol, transferIntent.amount, transferIntent.chainId, chainAccountsList, payment
            )
        ) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = transferIntent.amount;
            // If action is paid for with tokens and the payment token is the
            // transfer token, we need to add the max cost to the
            // amountNeededOnDst for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, transferIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: transferIntent.assetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: transferIntent.chainId,
                    recipient: transferIntent.sender,
                    blockTimestamp: transferIntent.blockTimestamp,
                    useQuotecall: useQuotecall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                List.addAction(actions, bridgeActions[i]);
                List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
            }
        }

        // If action is paid for with tokens and the payment token is not the transfer token, attempt to bridge some over if not enough
        // Note: The previous code block for bridging the transfer token already handles the case where payment token == transfer token
        if (payment.isToken && !Strings.stringEqIgnoreCase(payment.currency, transferIntent.assetSymbol)) {
            // Bridge over payment token if not enough
            uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, transferIntent.chainId);
            if (
                needsBridgedFunds(
                    payment.currency, maxCostOnDstChain, transferIntent.chainId, chainAccountsList, payment
                )
            ) {
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: payment.currency,
                        amountNeededOnDst: maxCostOnDstChain,
                        dstChainId: transferIntent.chainId,
                        recipient: transferIntent.sender,
                        blockTimestamp: transferIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                    List.addAction(actions, bridgeActions[i]);
                    List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
                }
            }
        }

        // Check if need to wrap/unwrap token to cover the transferIntent amount
        // If the existing balance is not enough to cover the transferIntent amount, wrap/unwrap the counterpart token here
        // NOTE: We prioritize unwrap/wrap in the dst chain over bridging, bridging logic checks for counterpart tokens when calculating the amounts to bridge.
        checkAndInsertWrapOrUnwrapAction(
            actions,
            quarkOperations,
            chainAccountsList,
            payment,
            transferIntent.assetSymbol,
            transferIntent.amount,
            transferIntent.chainId,
            transferIntent.sender,
            transferIntent.blockTimestamp,
            useQuotecall
        );

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

        List.addQuarkOperation(quarkOperations, operation);
        List.addAction(actions, action);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

        // Validate generated actions for affordability
        if (payment.isToken) {
            assertSufficientPaymentTokenBalances(
                actionsArray, chainAccountsList, transferIntent.chainId, transferIntent.sender
            );
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

        assertFundsAvailable(swapIntent.chainId, sellAssetSymbol, swapIntent.sellAmount, chainAccountsList, payment);

        bool useQuotecall = isMaxSwap;
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        if (needsBridgedFunds(sellAssetSymbol, swapIntent.sellAmount, swapIntent.chainId, chainAccountsList, payment)) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = swapIntent.sellAmount;
            // If action is paid for with tokens and the payment token is the
            // transfer token, we need to add the max cost to the
            // amountNeededOnDst for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, sellAssetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, swapIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: sellAssetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: swapIntent.chainId,
                    recipient: swapIntent.sender,
                    blockTimestamp: swapIntent.blockTimestamp,
                    useQuotecall: useQuotecall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                List.addAction(actions, bridgeActions[i]);
                List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
            }
        }

        // If action is paid for with tokens and the payment token is not the transfer token, attempt to bridge some over if not enough
        // Note: The previous code block for bridging the sell token already handles the case where payment token == transfer token
        if (payment.isToken && !Strings.stringEqIgnoreCase(payment.currency, sellAssetSymbol)) {
            // Bridge over payment token if not enough
            uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, swapIntent.chainId);
            if (needsBridgedFunds(payment.currency, maxCostOnDstChain, swapIntent.chainId, chainAccountsList, payment))
            {
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: payment.currency,
                        amountNeededOnDst: maxCostOnDstChain,
                        dstChainId: swapIntent.chainId,
                        recipient: swapIntent.sender,
                        blockTimestamp: swapIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                    List.addAction(actions, bridgeActions[i]);
                    List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
                }
            }
        }

        // Auto-wrap/unwrap
        checkAndInsertWrapOrUnwrapAction(
            actions,
            quarkOperations,
            chainAccountsList,
            payment,
            sellAssetSymbol,
            swapIntent.sellAmount,
            swapIntent.chainId,
            swapIntent.sender,
            swapIntent.blockTimestamp,
            useQuotecall
        );

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
        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        bool useQuotecall = false; // never use Quotecall
        bool paymentTokenIsCollateralAsset = false;

        assertFundsAvailable(
            borrowIntent.chainId,
            borrowIntent.collateralAssetSymbol,
            borrowIntent.collateralAmount,
            chainAccountsList,
            payment
        );

        if (Strings.stringEqIgnoreCase(borrowIntent.collateralAssetSymbol, payment.currency)) {
            paymentTokenIsCollateralAsset = true;
        }

        if (
            needsBridgedFunds(
                borrowIntent.collateralAssetSymbol,
                borrowIntent.collateralAmount,
                borrowIntent.chainId,
                chainAccountsList,
                payment
            )
        ) {
            uint256 amountNeededOnDst = borrowIntent.collateralAmount;
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, borrowIntent.collateralAssetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, borrowIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: borrowIntent.collateralAssetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: borrowIntent.chainId,
                    recipient: borrowIntent.borrower,
                    blockTimestamp: borrowIntent.blockTimestamp,
                    useQuotecall: useQuotecall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 j = 0; j < bridgeQuarkOperations.length; ++j) {
                List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[j]);
                List.addAction(actions, bridgeActions[j]);
            }
        }

        // when paying with tokens, you may need to bridge the payment token to cover the cost
        if (payment.isToken && !paymentTokenIsCollateralAsset) {
            uint256 maxCostOnDstChain = PaymentInfo.findMaxCost(payment, borrowIntent.chainId);
            // but if you're borrowing the payment token, you can use the
            // borrowed amount to cover the cost

            if (Strings.stringEqIgnoreCase(payment.currency, borrowIntent.assetSymbol)) {
                maxCostOnDstChain = Math.subtractFlooredAtZero(maxCostOnDstChain, borrowIntent.amount);
            }

            if (
                needsBridgedFunds(payment.currency, maxCostOnDstChain, borrowIntent.chainId, chainAccountsList, payment)
            ) {
                (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
                Actions.constructBridgeOperations(
                    Actions.BridgeOperationInfo({
                        assetSymbol: payment.currency,
                        amountNeededOnDst: maxCostOnDstChain,
                        dstChainId: borrowIntent.chainId,
                        recipient: borrowIntent.borrower,
                        blockTimestamp: borrowIntent.blockTimestamp,
                        useQuotecall: useQuotecall
                    }),
                    chainAccountsList,
                    payment
                );

                for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                    List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
                    List.addAction(actions, bridgeActions[i]);
                }
            }
        }

        // Auto-wrap on collateral supply
        checkAndInsertWrapOrUnwrapAction(
            actions,
            quarkOperations,
            chainAccountsList,
            payment,
            borrowIntent.collateralAssetSymbol,
            borrowIntent.collateralAmount,
            borrowIntent.chainId,
            borrowIntent.borrower,
            borrowIntent.blockTimestamp,
            useQuotecall
        );

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

        List.addQuarkOperation(quarkOperations, borrowQuarkOperation);
        List.addAction(actions, borrowAction);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

        // Validate generated actions for affordability
        if (payment.isToken) {
            uint256 supplementalPaymentTokenBalance = 0;
            if (Strings.stringEqIgnoreCase(payment.currency, borrowIntent.assetSymbol)) {
                supplementalPaymentTokenBalance += borrowIntent.amount;
            }

            assertSufficientPaymentTokenBalances(
                actionsArray,
                chainAccountsList,
                borrowIntent.chainId,
                borrowIntent.borrower,
                supplementalPaymentTokenBalance
            );
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

        assertFundsAvailable(repayIntent.chainId, repayIntent.assetSymbol, repayAmount, chainAccountsList, payment);

        List.DynamicArray memory actions = List.newList();
        List.DynamicArray memory quarkOperations = List.newList();

        if (needsBridgedFunds(repayIntent.assetSymbol, repayAmount, repayIntent.chainId, chainAccountsList, payment)) {
            // Note: Assumes that the asset uses the same # of decimals on each chain
            uint256 amountNeededOnDst = repayAmount;
            // If action is paid for with tokens and the payment token is the
            // repay token, we need to add the max cost to the
            // amountNeededOnDst for target chain
            if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, repayIntent.assetSymbol)) {
                amountNeededOnDst += PaymentInfo.findMaxCost(payment, repayIntent.chainId);
            }
            (IQuarkWallet.QuarkOperation[] memory bridgeQuarkOperations, Actions.Action[] memory bridgeActions) =
            Actions.constructBridgeOperations(
                Actions.BridgeOperationInfo({
                    assetSymbol: repayIntent.assetSymbol,
                    amountNeededOnDst: amountNeededOnDst,
                    dstChainId: repayIntent.chainId,
                    recipient: repayIntent.repayer,
                    blockTimestamp: repayIntent.blockTimestamp,
                    useQuotecall: useQuotecall
                }),
                chainAccountsList,
                payment
            );

            for (uint256 i = 0; i < bridgeQuarkOperations.length; ++i) {
                List.addAction(actions, bridgeActions[i]);
                List.addQuarkOperation(quarkOperations, bridgeQuarkOperations[i]);
            }
        }

        // Auto-wrap
        checkAndInsertWrapOrUnwrapAction(
            actions,
            quarkOperations,
            chainAccountsList,
            payment,
            repayIntent.assetSymbol,
            repayAmount,
            repayIntent.chainId,
            repayIntent.repayer,
            repayIntent.blockTimestamp,
            useQuotecall
        );

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

        List.addAction(actions, repayActions);
        List.addQuarkOperation(quarkOperations, repayQuarkOperations);

        // Convert actions and quark operations to arrays
        Actions.Action[] memory actionsArray = List.toActionArray(actions);
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray = List.toQuarkOperationArray(quarkOperations);

        // Validate generated actions for affordability
        if (payment.isToken) {
            // if you are withdrawing the payment token, you can pay with the
            // withdrawn funds
            uint256 supplementalPaymentTokenBalance = 0;
            if (Strings.stringEqIgnoreCase(payment.currency, repayIntent.collateralAssetSymbol)) {
                supplementalPaymentTokenBalance += repayIntent.collateralAmount;
            }

            assertSufficientPaymentTokenBalances(
                actionsArray,
                chainAccountsList,
                repayIntent.chainId,
                repayIntent.repayer,
                supplementalPaymentTokenBalance
            );
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

    // For some reason, funds that may otherwise be bridgeable or held by the user cannot
    // be made available to fulfill the transaction.
    // Funds cannot be bridged, e.g. no bridge exists
    // Funds cannot be withdrawn from Comet, e.g. no reserves
    function assertFundsAvailable(
        uint256 chainId,
        string memory assetSymbol,
        uint256 amount,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure {
        // If no funds need to be bridged, then this check is satisfied
        // TODO: We might still need to check the availability of funds on the target chain, e.g. see if
        // funds are locked in a lending protocol and can't be withdrawn
        if (!needsBridgedFunds(assetSymbol, amount, chainId, chainAccountsList, payment)) {
            return;
        }

        // Check each chain to see if there are enough action assets to be bridged over
        uint256 aggregateAssetBalance;
        uint256 aggregateMaxCosts;
        for (uint256 i = 0; i < chainAccountsList.length; ++i) {
            Accounts.AssetPositions memory positions =
                Accounts.findAssetPositions(assetSymbol, chainAccountsList[i].assetPositionsList);
            if (
                chainAccountsList[i].chainId == chainId
                    || BridgeRoutes.canBridge(chainAccountsList[i].chainId, chainId, assetSymbol)
            ) {
                aggregateAssetBalance += Accounts.sumBalances(positions);
                // If the user opts for paying with the payment token and the payment token is the transfer token, reduce
                // the available balance by the max cost because the max cost is reserved for paying the txn
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, assetSymbol)) {
                    aggregateMaxCosts += PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId);
                }
            }

            // If the asset has wrapper counterpart and can locally wrap/unwrap, accumulate the balance of the the counterpart
            // NOTE: Currently only at dst chain, and will ignore all the counterpart balance in other chains
            if (
                chainAccountsList[i].chainId == chainId
                    && TokenWrapper.hasWrapperContract(chainAccountsList[i].chainId, assetSymbol)
            ) {
                uint256 counterpartBalance =
                    getWrapperCounterpartBalance(assetSymbol, chainAccountsList[i].chainId, chainAccountsList);
                string memory counterpartSymbol =
                    TokenWrapper.getWrapperCounterpartSymbol(chainAccountsList[i].chainId, assetSymbol);
                // If the user opts for paying with payment token and the payment token is also the action token's counterpart
                // reduce the available balance by the max cost
                if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, counterpartSymbol)) {
                    counterpartBalance = Math.subtractFlooredAtZero(
                        counterpartBalance, PaymentInfo.findMaxCost(payment, chainAccountsList[i].chainId)
                    );
                }
                aggregateAssetBalance += counterpartBalance;
            }
        }

        uint256 aggregateAvailableAssetBalance =
            aggregateAssetBalance >= aggregateMaxCosts ? aggregateAssetBalance - aggregateMaxCosts : 0;
        if (aggregateAvailableAssetBalance < amount) {
            revert FundsUnavailable(assetSymbol, amount, aggregateAvailableAssetBalance);
        }
    }

    function getWrapperCounterpartBalance(
        string memory assetSymbol,
        uint256 chainId,
        Accounts.ChainAccounts[] memory chainAccountsList
    ) internal pure returns (uint256) {
        if (TokenWrapper.hasWrapperContract(chainId, assetSymbol)) {
            // Add counterpart balance to balanceOnChain
            return Accounts.getBalanceOnChain(
                TokenWrapper.getWrapperCounterpartSymbol(chainId, assetSymbol), chainId, chainAccountsList
            );
        }

        revert MissingWrapperCounterpart();
    }

    function needsBridgedFunds(
        string memory assetSymbol,
        uint256 amount,
        uint256 chainId,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) internal pure returns (bool) {
        uint256 balanceOnChain = Accounts.getBalanceOnChain(assetSymbol, chainId, chainAccountsList);
        // If action is paid for with tokens and the payment token is the transfer token, then add the payment max cost for the target chain to the amount needed
        uint256 amountNeededOnDstChain = amount;
        if (payment.isToken && Strings.stringEqIgnoreCase(payment.currency, assetSymbol)) {
            amountNeededOnDstChain += PaymentInfo.findMaxCost(payment, chainId);
        }

        // If there exists a counterpart token, try to wrap/unwrap first before attempting to bridge
        if (TokenWrapper.hasWrapperContract(chainId, assetSymbol)) {
            uint256 counterpartBalance = getWrapperCounterpartBalance(assetSymbol, chainId, chainAccountsList);
            // Subtract max cost if the counterpart token is the payment token
            if (
                payment.isToken
                    && Strings.stringEqIgnoreCase(
                        payment.currency, TokenWrapper.getWrapperCounterpartSymbol(chainId, assetSymbol)
                    )
            ) {
                // 0 if account can't afford to wrap/unwrap == can't use that balance
                counterpartBalance =
                    Math.subtractFlooredAtZero(counterpartBalance, PaymentInfo.findMaxCost(payment, chainId));
            }
            balanceOnChain += counterpartBalance;
        }

        return balanceOnChain < amountNeededOnDstChain;
    }

    /**
     * @dev If there is not enough of the asset to cover the amount and the asset has a counterpart asset,
     * insert a wrap/unwrap action to cover the gap in amount.
     */
    function checkAndInsertWrapOrUnwrapAction(
        List.DynamicArray memory actions,
        List.DynamicArray memory quarkOperations,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment,
        string memory assetSymbol,
        uint256 amount,
        uint256 chainId,
        address account,
        uint256 blockTimestamp,
        bool useQuotecall
    ) internal pure {
        // Check if inserting wrapOrUnwrap action is necessary
        uint256 assetBalanceOnChain = Accounts.getBalanceOnChain(assetSymbol, chainId, chainAccountsList);
        if (assetBalanceOnChain < amount && TokenWrapper.hasWrapperContract(chainId, assetSymbol)) {
            // If the asset has a wrapper counterpart, wrap/unwrap the token to cover the transferIntent amount
            string memory counterpartSymbol = TokenWrapper.getWrapperCounterpartSymbol(chainId, assetSymbol);

            // Wrap/unwrap the token to cover the amount
            (IQuarkWallet.QuarkOperation memory wrapOrUnwrapOperation, Actions.Action memory wrapOrUnwrapAction) =
            Actions.wrapOrUnwrapAsset(
                Actions.WrapOrUnwrapAsset({
                    chainAccountsList: chainAccountsList,
                    assetSymbol: counterpartSymbol,
                    // NOTE: Wrap/unwrap the amount needed to cover the amount
                    amount: amount - assetBalanceOnChain,
                    chainId: chainId,
                    sender: account,
                    blockTimestamp: blockTimestamp
                }),
                payment,
                useQuotecall
            );
            List.addQuarkOperation(quarkOperations, wrapOrUnwrapOperation);
            List.addAction(actions, wrapOrUnwrapAction);
        }
    }

    /**
     * @dev Asserts that each chain with a bridge action has enough payment
     * token to cover the payment token cost of the bridging action and that
     * the destination chain (once bridging is complete) will have a sufficient
     * amount of the payment token to cover the non-bridged actions.
     *
     * Optional `supplementalPaymentTokenBalance` param describes an amount of
     * the payment token that might have been received in the course of an
     * action (for example, withdrawing an asset from Compound), which would
     * therefore not be present in `chainAccountsList` but could be used to
     * cover action costs.
     */
    function assertSufficientPaymentTokenBalances(
        Actions.Action[] memory actions,
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 targetChainId,
        address account
    ) internal pure {
        return assertSufficientPaymentTokenBalances(actions, chainAccountsList, targetChainId, account, 0);
    }

    function assertSufficientPaymentTokenBalances(
        Actions.Action[] memory actions,
        Accounts.ChainAccounts[] memory chainAccountsList,
        uint256 targetChainId,
        address account,
        uint256 supplementalPaymentTokenBalance
    ) internal pure {
        Actions.Action[] memory bridgeActions = Actions.findActionsOfType(actions, Actions.ACTION_TYPE_BRIDGE);
        Actions.Action[] memory nonBridgeActions = Actions.findActionsNotOfType(actions, Actions.ACTION_TYPE_BRIDGE);

        string memory paymentTokenSymbol = nonBridgeActions[0].paymentTokenSymbol; // assumes all actions use the same payment token
        uint256 paymentTokenBridgeAmount = 0;
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

            if (Strings.stringEqIgnoreCase(bridgeActionContext.assetSymbol, paymentTokenSymbol)) {
                paymentTokenBridgeAmount += bridgeActionContext.amount;
            }
        }

        uint256 targetChainPaymentTokenBalance =
            Accounts.sumBalances(Accounts.findAssetPositions(paymentTokenSymbol, targetChainId, chainAccountsList)); // assumes that all non-bridge actions occur on the target chain
        uint256 paymentTokenCost = 0;

        for (uint256 i = 0; i < nonBridgeActions.length; ++i) {
            Actions.Action memory nonBridgeAction = nonBridgeActions[i];
            if (nonBridgeAction.chainId != targetChainId) {
                revert InvalidActionChain();
            }
            paymentTokenCost += nonBridgeAction.paymentMaxCost;

            if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_BORROW)) {
                continue;
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_MORPHO_REPAY)) {
                Actions.MorphoRepayActionContext memory morphoRepayActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.MorphoRepayActionContext));
                    if (morphoRepayActionContext.amount == type(uint256).max) {
                        paymentTokenCost += morphoRepayMaxAmount(
                                chainAccountsList,
                                morphoRepayActionContext.chainId,
                                morphoRepayActionContext.token,
                                morphoRepayActionContext.collateralToken,
                                account
                            );
                    } else {
                        paymentTokenCost += morphoRepayActionContext.amount;
                    }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_REPAY)) {
                Actions.RepayActionContext memory repayActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.RepayActionContext));
                if (Strings.stringEqIgnoreCase(repayActionContext.assetSymbol, paymentTokenSymbol)) {
                    if (repayActionContext.amount == type(uint256).max) {
                        paymentTokenCost += cometRepayMaxAmount(
                                chainAccountsList, repayActionContext.chainId, repayActionContext.comet, account
                            );
                    } else {
                        paymentTokenCost += repayActionContext.amount;
                    }
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_SUPPLY)) {
                Actions.SupplyActionContext memory cometSupplyActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.SupplyActionContext));
                if (Strings.stringEqIgnoreCase(cometSupplyActionContext.assetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += cometSupplyActionContext.amount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_SWAP)) {
                Actions.SwapActionContext memory swapActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.SwapActionContext));
                if (Strings.stringEqIgnoreCase(swapActionContext.inputAssetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += swapActionContext.inputAmount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_TRANSFER)) {
                Actions.TransferActionContext memory transferActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.TransferActionContext));
                if (Strings.stringEqIgnoreCase(transferActionContext.assetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += transferActionContext.amount;
                }
            } else if (
                Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_UNWRAP)
                    || Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_WRAP)
            ) {
                // XXX test that wrapping/unwrapping impacts paymentTokenCost
                Actions.WrapOrUnwrapActionContext memory wrapOrUnwrapActionContext =
                    abi.decode(nonBridgeAction.actionContext, (Actions.WrapOrUnwrapActionContext));
                if (Strings.stringEqIgnoreCase(wrapOrUnwrapActionContext.fromAssetSymbol, paymentTokenSymbol)) {
                    paymentTokenCost += wrapOrUnwrapActionContext.amount;
                }
            } else if (Strings.stringEqIgnoreCase(nonBridgeAction.actionType, Actions.ACTION_TYPE_WITHDRAW)) {
                continue;
            } else {
                revert InvalidActionType();
            }
        }

        if (
            paymentTokenCost
                > (targetChainPaymentTokenBalance + paymentTokenBridgeAmount + supplementalPaymentTokenBalance)
        ) {
            revert MaxCostTooHigh();
        }
    }
}
