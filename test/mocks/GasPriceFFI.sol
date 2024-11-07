// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "../../src/builder/Strings.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

contract GasPriceFFI {
    // TODO: Update to pass in list of chainIds
    function getGasPrices(
        string memory currency
    ) external pure returns (QuarkBuilderBase.GasPricesResult memory) {
        QuarkBuilderBase.GasPricesResult memory result;
        result.currency = currency;
        if (Strings.stringEq(currency, "usdc")) {
            result.currencyPrice = 2500 * 1e6;
        } else {
            revert("Unsupported currency");
        }

        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 1;
        chainIds[1] = 8453;

        QuarkBuilderBase.GasPrice[]
            memory gasPrices = new QuarkBuilderBase.GasPrice[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == 1) {
                gasPrices[i].chainId = 1;
                gasPrices[i].ethGasPrice = 8607726355;
            } else {
                gasPrices[i].chainId = 8453;
                gasPrices[i].ethGasPrice = 9919085;
            }
        }
        result.gasPrices = gasPrices;

        return result;
    }
}
