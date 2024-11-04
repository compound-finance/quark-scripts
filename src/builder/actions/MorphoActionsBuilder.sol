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

contract MorphoActionsBuilder is QuarkBuilderBase {
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
    ) external view returns (BuilderResult memory) {
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
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = borrowIntent.collateralAmount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = borrowIntent.collateralAssetSymbol;
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = borrowIntent.amount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = borrowIntent.assetSymbol;
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
    ) external view returns (BuilderResult memory) {
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

        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray;
        Actions.Action[] memory actionsArray;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = repayAmount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = repayIntent.assetSymbol;
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = repayIntent.collateralAmount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = repayIntent.collateralAssetSymbol;

            (quarkOperationsArray, actionsArray) = QuarkBuilderBase.collectAssetsForAction({
                actionIntent: QuarkBuilderBase.ActionIntent({
                    actor: repayIntent.repayer,
                    amountIns: amountIns,
                    assetSymbolIns: assetSymbolIns,
                    amountOuts: amountOuts,
                    assetSymbolOuts: assetSymbolOuts,
                    blockTimestamp: repayIntent.blockTimestamp,
                    chainId: repayIntent.chainId,
                    useQuotecall: useQuotecall,
                    bridgeEnabled: true,
                    autoWrapperEnabled: true
                }),
                chainAccountsList: chainAccountsList,
                payment: payment,
                actionQuarkOperation: repayQuarkOperations,
                action: repayActions
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

    struct MorphoRewardsClaimIntent {
        uint256 blockTimestamp;
        address claimer;
        uint256 chainId;
        address[] accounts;
        uint256[] claimables;
        address[] distributors;
        address[] rewards;
        bytes32[][] proofs;
    }

    function morphoClaimRewards(
        MorphoRewardsClaimIntent memory claimIntent,
        Accounts.ChainAccounts[] memory chainAccountsList,
        PaymentInfo.Payment memory payment
    ) external view returns (BuilderResult memory) {
        if (
            claimIntent.accounts.length != claimIntent.claimables.length
                || claimIntent.accounts.length != claimIntent.distributors.length
                || claimIntent.accounts.length != claimIntent.rewards.length
                || claimIntent.accounts.length != claimIntent.proofs.length
        ) {
            revert InvalidInput();
        }

        bool useQuotecall = false; // never use Quotecall

        (
            IQuarkWallet.QuarkOperation memory morphoClaimRewardsQuarkOperation,
            Actions.Action memory morphoClaimRewardsAction
        ) = Actions.morphoClaimRewards(
            Actions.MorphoClaimRewards({
                chainAccountsList: chainAccountsList,
                accounts: claimIntent.accounts,
                blockTimestamp: claimIntent.blockTimestamp,
                chainId: claimIntent.chainId,
                claimables: claimIntent.claimables,
                claimer: claimIntent.claimer,
                distributors: claimIntent.distributors,
                rewards: claimIntent.rewards,
                proofs: claimIntent.proofs
            }),
            payment
        );

        ActionIntent memory actionIntent;
        // Note: Scope to avoid stack too deep errors
        {
            string[] memory assetSymbolIns = new string[](claimIntent.rewards.length);
            for (uint256 i = 0; i < claimIntent.rewards.length; ++i) {
                assetSymbolIns[i] =
                    Accounts.findAssetPositions(claimIntent.rewards[i], claimIntent.chainId, chainAccountsList).symbol;
            }
            uint256[] memory amountOuts = new uint256[](0);
            string[] memory assetSymbolOuts = new string[](0);
            actionIntent = ActionIntent({
                actor: claimIntent.claimer,
                amountIns: claimIntent.claimables,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: claimIntent.blockTimestamp,
                chainId: claimIntent.chainId,
                useQuotecall: useQuotecall,
                bridgeEnabled: true,
                autoWrapperEnabled: true
            });
        }

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        collectAssetsForAction({
            actionIntent: actionIntent,
            chainAccountsList: chainAccountsList,
            payment: payment,
            actionQuarkOperation: morphoClaimRewardsQuarkOperation,
            action: morphoClaimRewardsAction
        });

        return BuilderResult({
            version: VERSION,
            actions: actionsArray,
            quarkOperations: quarkOperationsArray,
            paymentCurrency: payment.currency,
            eip712Data: EIP712Helper.eip712DataForQuarkOperations(quarkOperationsArray, actionsArray)
        });
    }
}
