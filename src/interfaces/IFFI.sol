// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

/// @dev Interface for foreign function interface (FFI) contracts
interface IFFI {
    function requestAcrossQuote(
        address inputToken,
        address outputToken,
        uint256 srcChain,
        uint256 dstChain,
        uint256 amount
    ) external pure returns (uint256 gasFee, uint256 variableFeePct);
}
