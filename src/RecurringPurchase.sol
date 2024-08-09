// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkScript} from "quark-core/src/QuarkScript.sol";

/**
 * @title Recurring Purchase Script
 * @notice Quark script that performs a swap on a regular interval.
 * @author Legend Labs, Inc.
 */
contract RecurringPurchase is QuarkScript {
    using SafeERC20 for IERC20;

    error InvalidInput();
    error PurchaseConditionNotMet();

    /**
     * @dev Note: This script uses the following storage layout:
     *         mapping(bytes32 hashedPurchaseConfig => uint256 nextPurchaseTime)
     *             where hashedPurchaseConfig = keccak256(PurchaseConfig)
     */

    /// @notice The configuration for a recurring purchase order
    struct PurchaseConfig {
        uint256 interval;
        SwapParams swapParams;
    }

    /// @notice The set of parameters for performing a swap
    struct SwapParams {
        address uniswapRouter;
        address recipient;
        address tokenFrom;
        uint256 amount;
        uint256 amountInMaximum; // Optional, for "exact out" swaps
        uint256 amountOutMinimum; // Optional, for "exact in" swaps
        uint256 deadline;
        bytes path;
    }

    /**
     * @notice Execute a swap given a configuration for a recurring purchase
     * @param config The configuration for a recurring purchase order
     */
    function purchase(PurchaseConfig calldata config) public {
        allowReplay();

        // Only one of the optional fields should be set
        if (config.swapParams.amountInMaximum > 0 && config.swapParams.amountOutMinimum > 0) {
            revert InvalidInput();
        }
        if (config.swapParams.amountInMaximum == 0 && config.swapParams.amountOutMinimum == 0) {
            revert InvalidInput();
        }

        bytes32 hashedConfig = hashConfig(config);
        uint256 nextPurchaseTime;
        if (read(hashedConfig) == 0) {
            nextPurchaseTime = block.timestamp;
        } else {
            nextPurchaseTime = uint256(read(hashedConfig));
        }

        // Check conditions
        if (block.timestamp < nextPurchaseTime) {
            revert PurchaseConditionNotMet();
        }

        // Update nextPurchaseTime
        write(hashedConfig, bytes32(nextPurchaseTime + config.interval));

        // Perform the swap
        SwapParams memory swapParams = config.swapParams;
        uint256 actualAmountIn;
        uint256 actualAmountOut;
        if (swapParams.amountInMaximum > 0) {
            // Exact out swap
            IERC20(swapParams.tokenFrom).forceApprove(swapParams.uniswapRouter, swapParams.amountInMaximum);
            actualAmountIn = ISwapRouter(swapParams.uniswapRouter).exactOutput(
                ISwapRouter.ExactOutputParams({
                    path: swapParams.path,
                    recipient: swapParams.recipient,
                    deadline: swapParams.deadline,
                    amountOut: swapParams.amount,
                    amountInMaximum: swapParams.amountInMaximum
                })
            );
            actualAmountOut = swapParams.amount;
        } else if (swapParams.amountOutMinimum > 0) {
            // Exact in swap
            IERC20(swapParams.tokenFrom).forceApprove(swapParams.uniswapRouter, swapParams.amount);
            actualAmountOut = ISwapRouter(swapParams.uniswapRouter).exactInput(
                ISwapRouter.ExactInputParams({
                    path: swapParams.path,
                    recipient: swapParams.recipient,
                    deadline: swapParams.deadline,
                    amountIn: swapParams.amount,
                    amountOutMinimum: swapParams.amountOutMinimum
                })
            );
            actualAmountIn = swapParams.amount;
        }

        // Approvals to external contracts should always be reset to 0
        IERC20(swapParams.tokenFrom).forceApprove(swapParams.uniswapRouter, 0);
    }

    /// @notice Cancel the recurring purchase for the current nonce
    function cancel() external {
        // Not explicitly clearing the nonce just cancels the replayable txn
    }

    /// @notice Deterministically hash the purchase configuration
    function hashConfig(PurchaseConfig calldata config) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                config.interval,
                abi.encodePacked(
                    config.swapParams.uniswapRouter,
                    config.swapParams.recipient,
                    config.swapParams.tokenFrom,
                    config.swapParams.amount,
                    config.swapParams.amountInMaximum,
                    config.swapParams.amountOutMinimum,
                    config.swapParams.deadline,
                    config.swapParams.path
                )
            )
        );
    }
}
