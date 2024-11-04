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

contract MorphoVaultActionsBuilder is QuarkBuilderBase {
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
    ) external view returns (BuilderResult memory) {
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

        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray;
        Actions.Action[] memory actionsArray;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = supplyIntent.amount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = supplyIntent.assetSymbol;
            uint256[] memory amountIns = new uint256[](0);
            string[] memory assetSymbolIns = new string[](0);

            (quarkOperationsArray, actionsArray) = collectAssetsForAction({
                actionIntent: ActionIntent({
                    actor: supplyIntent.sender,
                    amountIns: amountIns,
                    assetSymbolIns: assetSymbolIns,
                    amountOuts: amountOuts,
                    assetSymbolOuts: assetSymbolOuts,
                    blockTimestamp: supplyIntent.blockTimestamp,
                    chainId: supplyIntent.chainId,
                    useQuotecall: useQuotecall,
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
    ) external view returns (BuilderResult memory) {
        // XXX confirm that you actually have the amount to withdraw

        bool isMaxWithdraw = withdrawIntent.amount == type(uint256).max;
        bool useQuotecall = false; // never use Quotecall

        uint256 actualWithdrawAmount = withdrawIntent.amount;
        if (isMaxWithdraw) {
            actualWithdrawAmount = 0;
            // when doing a maxWithdraw of the payment token, add the account's supplied balance
            // as supplemental payment token balance
            Accounts.MorphoVaultPositions memory morphoVaultPositions = Accounts.findMorphoVaultPositions(
                withdrawIntent.chainId,
                Accounts.findAssetPositions(withdrawIntent.assetSymbol, withdrawIntent.chainId, chainAccountsList).asset,
                chainAccountsList
            );

            for (uint256 i = 0; i < morphoVaultPositions.accounts.length; ++i) {
                if (morphoVaultPositions.accounts[i] == withdrawIntent.withdrawer) {
                    actualWithdrawAmount += morphoVaultPositions.balances[i];
                }
            }
        }

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

        ActionIntent memory actionIntent;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = actualWithdrawAmount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = withdrawIntent.assetSymbol;
            uint256[] memory amountOuts = new uint256[](0);
            string[] memory assetSymbolOuts = new string[](0);
            actionIntent = ActionIntent({
                actor: withdrawIntent.withdrawer,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: withdrawIntent.blockTimestamp,
                chainId: withdrawIntent.chainId,
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
            actionQuarkOperation: cometWithdrawQuarkOperation,
            action: cometWithdrawAction
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
