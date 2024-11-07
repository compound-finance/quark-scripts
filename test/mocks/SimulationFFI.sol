// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {Actions} from "src/builder/actions/Actions.sol";
import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";
import "../../src/builder/Strings.sol";

contract SimulationFFI {
    // Mock simulate FFI implementation
    function simulate(IQuarkWallet.QuarkOperation[] memory quarkOperations, Actions.Action[] memory actionsArray)
        external
        pure
        returns (QuarkBuilderBase.Simulation[] memory)
    {
        QuarkBuilderBase.Simulation[] memory simulations = new QuarkBuilderBase.Simulation[](quarkOperations.length);
        for (uint256 i = 0; i < quarkOperations.length; i++) {
            Actions.Action memory action = actionsArray[i];

            uint256 gasPrice;
            if (action.chainId == 1) {
                gasPrice = 8607726355;
            } else {
                gasPrice = 9919085;
            }
            uint256 operationGasUsed = 100000;
            uint256 ethPriceInUSD = 2500;

            uint256 currencyScale;
            if (Strings.stringEq(action.paymentMethod, "OFFCHAIN")) {
                currencyScale = 1e2;
            } else {
                currencyScale = 1e6;
                operationGasUsed += 135_000; // Estimated paycall buffer
            }

            uint256 operationCurrencyEstimate = operationGasUsed * gasPrice * ethPriceInUSD * currencyScale / 1e18;
            if (operationCurrencyEstimate == 0) {
                operationCurrencyEstimate = 1;
            }

            simulations[i] = QuarkBuilderBase.Simulation({
                chainId: action.chainId,
                currency: getPaymentCurrency(action),
                operationGasUsed: operationGasUsed,
                factoryGasUsed: 0,
                ethGasPrice: gasPrice,
                operationCurrencyEstimate: operationCurrencyEstimate,
                factoryCurrencyEstimate: 0,
                currencyEstimate: operationCurrencyEstimate
            });
        }
        return simulations;
    }

    function getPaymentCurrency(Actions.Action memory action) internal pure returns (string memory currency) {
        if (Strings.stringEq(action.paymentMethod, "OFFCHAIN")) {
            currency = "usd";
        } else {
            currency = "usdc";
        }
    }
}
