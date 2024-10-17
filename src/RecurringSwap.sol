// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {AggregatorV3Interface} from "src/vendor/chainlink/AggregatorV3Interface.sol";
import {ISwapRouter02, IV3SwapRouter} from "src/vendor/uniswap-swap-router-contracts/ISwapRouter02.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkScript} from "quark-core/src/QuarkScript.sol";

/**
 * @title Recurring Swap Script
 * @notice Quark script that performs a swap on a regular interval.
 * @author Legend Labs, Inc.
 */
contract RecurringSwap is QuarkScript {
    using SafeERC20 for IERC20;

    error BadPrice();
    error InvalidInput();
    error SwapWindowClosed(uint256 currentWindowStartTime, uint256 windowLength, uint256 currentTime);
    error SwapWindowNotOpen(uint256 nextWindowStartTime, uint256 windowLength, uint256 currentTime);

    /// @notice Emitted when a swap is executed
    event SwapExecuted(
        address indexed sender,
        address indexed recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes path
    );

    /// @notice The base slippage factor where `1e18` represents 100% slippage tolerance
    uint256 public constant BASE_SLIPPAGE_FACTOR = 1e18;

    /// @notice The factor to scale up intermediate values by to preserve precision during multiplication and division
    uint256 public constant PRECISION_FACTOR = 1e18;

    /**
     * @dev Note: This script uses the following storage layout in the Quark wallet:
     *         mapping(bytes32 hashedSwapConfig => uint256 nextWindowStart)
     *             where hashedSwapConfig = getNonceIsolatedKey(keccak256(SwapConfig))
     */

    /// @notice Parameters for a recurring swap order
    struct SwapConfig {
        SwapWindow swapWindow;
        SwapParams swapParams;
        SlippageParams slippageParams;
    }

    /// @notice Parameters for performing a swap
    struct SwapWindow {
        /// @dev Timestamp of the start of the first swap window
        uint256 startTime;
        /// @dev Measured in seconds; time between the start of each swap window
        uint256 interval;
        /// @dev Measured in seconds; defines how long the window for executing the swap remains open
        uint256 length;
    }

    /// @notice Parameters for performing a swap
    struct SwapParams {
        address uniswapRouter;
        address recipient;
        address tokenIn;
        address tokenOut;
        /// @dev The amount for tokenIn if exact in; the amount for tokenOut if exact out
        uint256 amount;
        /// @dev False for exact in; true for exact out
        bool isExactOut;
        bytes path;
    }

    /// @notice Parameters for controlling slippage in a swap operation
    struct SlippageParams {
        /// @dev Maximum acceptable slippage, expressed as a percentage where 100% = 1e18
        uint256 maxSlippage;
        /// @dev Price feed addresses for determining market exchange rates between token pairs
        /// Example: For SUSHI -> SNX swap, use [SUSHI/ETH feed, SNX/ETH feed]
        address[] priceFeeds;
        /// @dev Flags indicating whether each corresponding price feed should be inverted
        /// Example: For USDC -> ETH swap, use [true] with [ETH/USD feed] to get ETH per USDC
        bool[] shouldInvert;
    }

    /**
     * @notice Execute a swap given a configuration for a recurring swap
     * @param config The configuration for a recurring swap order
     */
    function swap(SwapConfig calldata config) public {
        if (config.slippageParams.priceFeeds.length == 0) {
            revert InvalidInput();
        }
        if (config.slippageParams.priceFeeds.length != config.slippageParams.shouldInvert.length) {
            revert InvalidInput();
        }

        bytes32 hashedConfig = _hashConfig(config);
        uint256 nextWindowStart;
        if (read(hashedConfig) == 0) {
            nextWindowStart = config.swapWindow.startTime;
        } else {
            nextWindowStart = uint256(read(hashedConfig));
        }

        // Check that swap window is open
        if (block.timestamp < nextWindowStart) {
            revert SwapWindowNotOpen(nextWindowStart, config.swapWindow.length, block.timestamp);
        }

        // Find the last window start time and the next window start time
        uint256 completedIntervals = (block.timestamp - config.swapWindow.startTime) / config.swapWindow.interval;
        uint256 lastWindowStart = config.swapWindow.startTime + (completedIntervals * config.swapWindow.interval);
        uint256 updatedNextWindowStart = lastWindowStart + config.swapWindow.interval;

        // Check that current swap window (lastWindowStart + swapWindow.length) is not closed
        if (block.timestamp > lastWindowStart + config.swapWindow.length) {
            revert SwapWindowClosed(lastWindowStart, config.swapWindow.length, block.timestamp);
        }

        write(hashedConfig, bytes32(updatedNextWindowStart));

        (uint256 amountIn, uint256 amountOut) = _calculateSwapAmounts(config);
        (uint256 actualAmountIn, uint256 actualAmountOut) =
            _executeSwap({swapParams: config.swapParams, amountIn: amountIn, amountOut: amountOut});

        // Emit the swap event
        emit SwapExecuted(
            msg.sender,
            config.swapParams.recipient,
            config.swapParams.tokenIn,
            config.swapParams.tokenOut,
            actualAmountIn,
            actualAmountOut,
            config.swapParams.path
        );
    }

    /**
     * @notice Calculates the amounts of tokens required for a swap based on the given configuration
     * @param config The configuration for the swap including swap parameters and slippage parameters
     * @return amountIn The amount of `tokenIn` required for the swap
     * @return amountOut The amount of `tokenOut` expected from the swap
     * @dev This function handles both "exact in" and "exact out" scenarios. It adjusts amounts based on price feeds and decimals.
     *      For "exact out", it calculates the required `amountIn` to achieve the desired `amountOut`.
     *      For "exact in", it calculates the expected `amountOut` for the provided `amountIn`.
     *      The function also applies slippage tolerance to the calculated amounts.
     */
    function _calculateSwapAmounts(SwapConfig calldata config)
        internal
        view
        returns (uint256 amountIn, uint256 amountOut)
    {
        SwapParams memory swapParams = config.swapParams;
        // We multiply intermediate values by 1e18 to preserve precision during multiplication and division
        amountIn = swapParams.amount * PRECISION_FACTOR;
        amountOut = swapParams.amount * PRECISION_FACTOR;

        for (uint256 i = 0; i < config.slippageParams.priceFeeds.length; ++i) {
            // Get price from oracle
            AggregatorV3Interface priceFeed = AggregatorV3Interface(config.slippageParams.priceFeeds[i]);
            (, int256 rawPrice,,,) = priceFeed.latestRoundData();
            if (rawPrice <= 0) {
                revert BadPrice();
            }
            uint256 price = uint256(rawPrice);
            uint256 priceScale = 10 ** uint256(priceFeed.decimals());

            if (swapParams.isExactOut) {
                // For exact out, we need to adjust amountIn by going backwards through the price feeds
                amountIn = config.slippageParams.shouldInvert[i]
                    ? amountIn * price / priceScale
                    : amountIn * priceScale / price;
            } else {
                // For exact in, we need to adjust amountOut by going forwards through price feeds
                amountOut = config.slippageParams.shouldInvert[i]
                    ? amountOut * priceScale / price
                    : amountOut * price / priceScale;
            }
        }

        uint256 tokenInDecimals = IERC20Metadata(swapParams.tokenIn).decimals();
        uint256 tokenOutDecimals = IERC20Metadata(swapParams.tokenOut).decimals();

        // Scale amountIn to the correct amount of decimals and apply a slippage tolerance to it
        if (swapParams.isExactOut) {
            amountIn = _rescale({amount: amountIn, fromDecimals: tokenOutDecimals, toDecimals: tokenInDecimals});
            amountIn = (amountIn * (BASE_SLIPPAGE_FACTOR + config.slippageParams.maxSlippage)) / BASE_SLIPPAGE_FACTOR
                / PRECISION_FACTOR;
            amountOut /= PRECISION_FACTOR;
        } else {
            amountOut = _rescale({amount: amountOut, fromDecimals: tokenInDecimals, toDecimals: tokenOutDecimals});
            amountOut = (amountOut * (BASE_SLIPPAGE_FACTOR - config.slippageParams.maxSlippage)) / BASE_SLIPPAGE_FACTOR
                / PRECISION_FACTOR;
            amountIn /= PRECISION_FACTOR;
        }
    }

    /**
     * @notice Executes the swap based on the provided parameters
     * @param swapParams The parameters for the swap including router address, token addresses, and amounts
     * @param amountIn The amount of `tokenIn` to be used in the swap
     * @param amountOut The amount of `tokenOut` to be received from the swap
     * @return actualAmountIn The actual amount of input tokens used in the swap
     * @return actualAmountOut The actual amount of output tokens received from the swap
     * @dev This function performs the swap using either the exact input or exact output method, depending on the configuration.
     *      It also handles the approval of tokens for the swap router and resets the approval after the swap.
     */
    function _executeSwap(SwapParams memory swapParams, uint256 amountIn, uint256 amountOut)
        internal
        returns (uint256 actualAmountIn, uint256 actualAmountOut)
    {
        IERC20(swapParams.tokenIn).forceApprove(swapParams.uniswapRouter, amountIn);

        if (swapParams.isExactOut) {
            // Exact out swap
            actualAmountIn = ISwapRouter02(swapParams.uniswapRouter).exactOutput(
                IV3SwapRouter.ExactOutputParams({
                    path: swapParams.path,
                    recipient: swapParams.recipient,
                    amountOut: amountOut,
                    amountInMaximum: amountIn
                })
            );
            actualAmountOut = amountOut;
        } else {
            // Exact in swap
            actualAmountOut = ISwapRouter02(swapParams.uniswapRouter).exactInput(
                IV3SwapRouter.ExactInputParams({
                    path: swapParams.path,
                    recipient: swapParams.recipient,
                    amountIn: amountIn,
                    amountOutMinimum: amountOut
                })
            );
            actualAmountIn = amountIn;
        }

        // Approvals to external contracts should always be reset to 0
        IERC20(swapParams.tokenIn).forceApprove(swapParams.uniswapRouter, 0);
    }

    /**
     * @notice Scales an amount from one decimal precision to another decision precision
     * @param amount The amount to be scaled
     * @param fromDecimals The number of decimals in the source precision
     * @param toDecimals The number of decimals in the target precision
     * @return The scaled amount adjusted to the target precision
     */
    function _rescale(uint256 amount, uint256 fromDecimals, uint256 toDecimals) internal pure returns (uint256) {
        if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals));
        } else if (fromDecimals > toDecimals) {
            return amount / (10 ** (fromDecimals - toDecimals));
        }

        return amount;
    }

    /// @notice Deterministically hash the swap configuration
    function _hashConfig(SwapConfig calldata config) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                config.swapWindow.startTime,
                config.swapWindow.interval,
                config.swapWindow.length,
                abi.encodePacked(
                    config.swapParams.uniswapRouter,
                    config.swapParams.recipient,
                    config.swapParams.tokenIn,
                    config.swapParams.tokenOut,
                    config.swapParams.amount,
                    config.swapParams.isExactOut,
                    config.swapParams.path
                ),
                abi.encodePacked(
                    config.slippageParams.maxSlippage,
                    keccak256(abi.encodePacked(config.slippageParams.priceFeeds)),
                    keccak256(abi.encodePacked(config.slippageParams.shouldInvert))
                )
            )
        );
    }
}
