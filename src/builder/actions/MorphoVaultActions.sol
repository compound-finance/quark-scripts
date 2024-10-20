// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Actions} from "src/builder/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {EIP712Helper} from "src/builder/EIP712Helper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

contract MorphoVaultActions is QuarkBuilderBase {
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

        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray;
        Actions.Action[] memory actionsArray;
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = supplyIntent.amount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = supplyIntent.assetSymbol;
            uint256[] memory amountIns = new uint256[](0);
            string[] memory assetSymbolIns = new string[](0);

            (quarkOperationsArray, actionsArray) = QuarkBuilderBase.collectAssetsForAction({
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
    ) external pure returns (BuilderResult memory) {
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

        IQuarkWallet.QuarkOperation[] memory quarkOperationsArray;
        Actions.Action[] memory actionsArray;
        {
            uint256[] memory amountIns = new uint256[](1);
            amountIns[0] = actualWithdrawAmount;
            string[] memory assetSymbolIns = new string[](1);
            assetSymbolIns[0] = withdrawIntent.assetSymbol;
            uint256[] memory amountOuts = new uint256[](0);
            string[] memory assetSymbolOuts = new string[](0);

            (quarkOperationsArray, actionsArray) = QuarkBuilderBase.collectAssetsForAction({
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
        }
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