// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Actions} from "src/builder/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {EIP712Helper} from "src/builder/EIP712Helper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

contract Morpho is QuarkBuilderBase {
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

        QuarkBuilderBase.ActionIntent memory actionIntent;
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = borrowIntent.amount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = borrowIntent.assetSymbol;
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = borrowIntent.collateralAmount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = borrowIntent.collateralAssetSymbol;
            actionIntent = QuarkBuilderBase.ActionIntent({
                actor: borrowIntent.borrower,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: borrowIntent.blockTimestamp,
                chainId: borrowIntent.chainId,
                useQuotecall: useQuotecall,
                bridgeEnabled: true,
                autoWrapperEnabled: true,
                chainAccountsList: chainAccountsList,
                payment: payment,
                quarkOperation: borrowQuarkOperation,
                action: borrowAction
            });
        }

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
            QuarkBuilderBase.collectAssetsForAction(actionIntent);
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

        QuarkBuilderBase.ActionIntent memory actionIntent;
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = repayAmount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = repayIntent.assetSymbol;
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = repayIntent.collateralAmount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = repayIntent.collateralAssetSymbol;
            actionIntent = QuarkBuilderBase.ActionIntent({
                actor: repayIntent.repayer,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: repayIntent.blockTimestamp,
                chainId: repayIntent.chainId,
                useQuotecall: useQuotecall,
                bridgeEnabled: true,
                autoWrapperEnabled: true,
                chainAccountsList: chainAccountsList,
                payment: payment,
                quarkOperation: repayQuarkOperations,
                action: repayActions
            });
        }

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
            QuarkBuilderBase.collectAssetsForAction(actionIntent);

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }
}
