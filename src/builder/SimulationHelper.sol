// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

library SimulationHelper {
    // Estimate from CCTP bridge action (including paycall): 0x894f0e4c944db179d0f573aab2c349d7f6df07690ac3772cf744e73a9208a79d
    uint256 constant BRIDGE_GAS_AMOUNT = 430_000;

    function getMaxCost(
        uint256 chainId,
        QuarkBuilderBase.GasPricesResult memory gasPrices,
        uint256 estimatedGas
    ) internal pure returns (uint256) {
        QuarkBuilderBase.GasPrice memory gasPrice = getGasPrice(
            chainId,
            gasPrices
        );

        return
            (estimatedGas * gasPrice.ethGasPrice * gasPrices.currencyPrice) /
            1e18;
    }

    function getGasPrice(
        uint256 chainId,
        QuarkBuilderBase.GasPricesResult memory gasPrices
    ) internal pure returns (QuarkBuilderBase.GasPrice memory) {
        QuarkBuilderBase.GasPrice memory gasPrice;

        for (uint256 i = 0; i < gasPrices.gasPrices.length; i++) {
            if (gasPrices.gasPrices[i].chainId == chainId) {
                gasPrice = gasPrices.gasPrices[i];
                break;
            }
        }

        return gasPrice;
    }
}
