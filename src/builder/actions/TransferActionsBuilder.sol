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

contract TransferActionsBuilder is QuarkBuilderBase {
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
    ) external view returns (BuilderResult memory) {
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

        ActionIntent memory actionIntent;
        // Note: Scope to avoid stack too deep errors
        {
            uint256[] memory amountOuts = new uint256[](1);
            amountOuts[0] = transferIntent.amount;
            string[] memory assetSymbolOuts = new string[](1);
            assetSymbolOuts[0] = transferIntent.assetSymbol;
            uint256[] memory amountIns = new uint256[](0);
            string[] memory assetSymbolIns = new string[](0);
            actionIntent = ActionIntent({
                actor: transferIntent.sender,
                amountIns: amountIns,
                assetSymbolIns: assetSymbolIns,
                amountOuts: amountOuts,
                assetSymbolOuts: assetSymbolOuts,
                blockTimestamp: transferIntent.blockTimestamp,
                chainId: transferIntent.chainId,
                useQuotecall: useQuotecall,
                bridgeEnabled: true,
                autoWrapperEnabled: true
            });
        }

        (IQuarkWallet.QuarkOperation[] memory quarkOperationsArray, Actions.Action[] memory actionsArray) =
        simulateAndGetActions({
            actionIntent: actionIntent,
            chainAccountsList: chainAccountsList,
            payment: payment,
            actionQuarkOperation: operation,
            action: action
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
