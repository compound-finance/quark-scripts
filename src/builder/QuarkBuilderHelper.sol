// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {BridgeRoutes} from "./BridgeRoutes.sol";

/**
 * @title Quark Builder Helper
 * @notice External-facing functions that might be helpful for those using the QuarkBuilder
 */
contract QuarkBuilderHelper {
    /* ===== Constants ===== */

    uint256 constant PAYMENT_COST_BUFFER = 1.2e18;
    uint256 constant BUFFER_SCALE = 1e18;

    function canBridge(uint256 srcChainId, uint256 dstChainId, string memory assetSymbol)
        external
        pure
        returns (bool)
    {
        return BridgeRoutes.canBridge(srcChainId, dstChainId, assetSymbol);
    }

    function addBufferToPaymentCost(uint256 maxPaymentCost) external pure returns (uint256) {
        return maxPaymentCost * PAYMENT_COST_BUFFER / BUFFER_SCALE;
    }
}
