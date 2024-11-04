// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Actions} from "src/builder/actions/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {BridgeRoutes} from "src/builder/BridgeRoutes.sol";
import {EIP712Helper} from "src/builder/EIP712Helper.sol";
import {Math} from "src/lib/Math.sol";
import {MorphoInfo} from "src/builder/MorphoInfo.sol";
import {Strings} from "src/builder/Strings.sol";
import {PaycallWrapper} from "src/builder/PaycallWrapper.sol";
import {QuotecallWrapper} from "src/builder/QuotecallWrapper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {TokenWrapper} from "src/builder/TokenWrapper.sol";
import {QuarkOperationHelper} from "src/builder/QuarkOperationHelper.sol";
import {List} from "src/builder/List.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

contract CometActionsBuilder is QuarkBuilderBase {
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
    ) external view returns (BuilderResult memory /* builderResult */ ) {
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

        QuarkBuilderBase.ActionIntent memory actionIntent;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = repayAmount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = repayIntent.assetSymbol;
            actionIntent = QuarkBuilderBase.ActionIntent({
                actor: repayIntent.repayer,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                amountIns: repayIntent.collateralAmounts,
                assetSymbolIns: repayIntent.collateralAssetSymbols,
                blockTimestamp: repayIntent.blockTimestamp,
                chainId: repayIntent.chainId,
                useQuotecall: useQuotecall,
                bridgeEnabled: true,
                autoWrapperEnabled: true
            });
        }

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: actionIntent,
            chainAccountsList: chainAccountsList,
            payment: payment,
            actionQuarkOperation: repayQuarkOperation,
            action: repayAction
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
    ) external view returns (BuilderResult memory /* builderResult */ ) {
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

        QuarkBuilderBase.ActionIntent memory actionIntent;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = borrowIntent.amount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = borrowIntent.assetSymbol;
            actionIntent = QuarkBuilderBase.ActionIntent({
                actor: borrowIntent.borrower,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: borrowIntent.collateralAmounts,
                assetSymbolOuts: borrowIntent.collateralAssetSymbols,
                blockTimestamp: borrowIntent.blockTimestamp,
                chainId: borrowIntent.chainId,
                useQuotecall: useQuotecall,
                bridgeEnabled: true,
                autoWrapperEnabled: true
            });
        }

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        QuarkBuilderBase.collectAssetsForAction({
            actionIntent: actionIntent,
            chainAccountsList: chainAccountsList,
            payment: payment,
            actionQuarkOperation: borrowQuarkOperation,
            action: borrowAction
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
    ) external view returns (BuilderResult memory /* builderResult */ ) {
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

        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray;
        Actions.Action[] memory actionsArray;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = cometSupplyIntent.amount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = cometSupplyIntent.assetSymbol;
            uint256[] memory amountIns = new uint256[](0);
            string[] memory assetSymbolIns = new string[](0);

            (quarkOperationsArray, actionsArray) = QuarkBuilderBase.collectAssetsForAction({
                actionIntent: QuarkBuilderBase.ActionIntent({
                    actor: cometSupplyIntent.sender,
                    amountIns: amountIns,
                    assetSymbolIns: assetSymbolIns,
                    amountOuts: amountOuts,
                    assetSymbolOuts: assetSymbolOuts,
                    blockTimestamp: cometSupplyIntent.blockTimestamp,
                    chainId: cometSupplyIntent.chainId,
                    useQuotecall: isMaxSupply,
                    bridgeEnabled: true,
                    autoWrapperEnabled: true
                }),
                chainAccountsList: chainAccountsList,
                payment: payment,
                actionQuarkOperation: supplyQuarkOperation,
                action: supplyAction
            });
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
    ) external view returns (BuilderResult memory) {
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
        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray;
        Actions.Action[] memory actionsArray;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = actualWithdrawAmount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = cometWithdrawIntent.assetSymbol;
            uint256[] memory amountOuts = new uint256[](0);
            string[] memory assetSymbolOuts = new string[](0);

            (quarkOperationsArray, actionsArray) = QuarkBuilderBase.collectAssetsForAction({
                actionIntent: QuarkBuilderBase.ActionIntent({
                    actor: cometWithdrawIntent.withdrawer,
                    amountIns: amountIns,
                    assetSymbolIns: assetSymbolIns,
                    amountOuts: amountOuts,
                    assetSymbolOuts: assetSymbolOuts,
                    blockTimestamp: cometWithdrawIntent.blockTimestamp,
                    chainId: cometWithdrawIntent.chainId,
                    useQuotecall: useQuotecall,
                    bridgeEnabled: true,
                    autoWrapperEnabled: true
                }),
                chainAccountsList: chainAccountsList,
                payment: payment,
                actionQuarkOperation: cometWithdrawQuarkOperation,
                action: cometWithdrawAction
            });
        }

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }
}
