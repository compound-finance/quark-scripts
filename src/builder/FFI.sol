// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {IAcrossFFI} from "src/interfaces/IAcrossFFI.sol";

/**
 * @title Foreign Function Interface (FFI) Helper
 * @notice Defines the addresses of reserved FFIs and methods for calling them
 */
library FFI {
    /* FFI Addresses (starts from 0xFF1000, FFI with 100 reserved addresses) */
    address constant ACROSS_FFI_ADDRESS = address(0xFF1000);

    function requestAcrossQuote(
        address inputToken,
        address outputToken,
        uint256 srcChain,
        uint256 dstChain,
        uint256 amount
    ) internal pure returns (uint256 gasFee, uint256 variableFeePct) {
        // Make FFI call to fetch a quote from Across API
        return IAcrossFFI(ACROSS_FFI_ADDRESS).requestAcrossQuote(inputToken, outputToken, srcChain, dstChain, amount);
    }
}
