// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

/// @dev Interface for Across v3 Spoke Pool
/// Reference: https://github.com/across-protocol/contracts/blob/master/contracts/interfaces/V3SpokePoolInterface.sol
interface IAcrossV3SpokePool {
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable;
}
