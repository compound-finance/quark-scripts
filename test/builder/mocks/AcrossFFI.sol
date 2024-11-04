// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {IAcrossFFI} from "src/interfaces/IAcrossFFI.sol";

contract AcrossFFI is IAcrossFFI {
    function requestAcrossQuote(
        address, /* inputToken */
        address, /* outputToken */
        uint256, /* srcChain */
        uint256, /* dstChain */
        uint256 /* amount */
    ) external pure override returns (uint256 gasFee, uint256 variableFeePct) {
        return (1e6, 0.01e18);
    }
}
