// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {AggregatorV3Interface} from "src/vendor/chainlink/AggregatorV3Interface.sol";
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

    error BadPrice();
    error InvalidInput();
    error PurchaseConditionNotMet();

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

    /**
     * @dev Note: This script uses the following storage layout in the QuarkStateManager:
     *         mapping(bytes32 hashedPurchaseConfig => uint256 nextPurchaseTime)
     *             where hashedPurchaseConfig = keccak256(PurchaseConfig)
     */

    /// @notice Parameters for a recurring purchase order
    struct PurchaseConfig {
        uint256 interval;
        SwapParams swapParams;
        SlippageParams slippageParams;
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
        uint256 deadline;
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
        bool[] shouldReverses;
    }

    /// @notice Cancel the recurring purchase for the current nonce
    function cancel() external {
        // Not explicitly clearing the nonce just cancels the replayable txn
    }

    /**
     * @notice Execute a swap given a configuration for a recurring purchase
     * @param config The configuration for a recurring purchase order
     */
    function purchase(PurchaseConfig calldata config) public {
        allowReplay();

        if (config.slippageParams.priceFeeds.length == 0) {
            revert InvalidInput();
        }
        if (config.slippageParams.priceFeeds.length != config.slippageParams.shouldReverses.length) {
            revert InvalidInput();
        }

        bytes32 hashedConfig = _hashConfig(config);
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

        (uint256 amountIn, uint256 amountOut) = _calculateSwapAmounts(config);
        (uint256 actualAmountIn, uint256 actualAmountOut) = _executeSwap(config.swapParams, amountIn, amountOut);

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
    function _calculateSwapAmounts(PurchaseConfig calldata config)
        internal
        view
        returns (uint256 amountIn, uint256 amountOut)
    {
        SwapParams memory swapParams = config.swapParams;
        amountIn = swapParams.amount;
        amountOut = swapParams.amount;

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
                amountIn = config.slippageParams.shouldReverses[i]
                    ? amountIn * price / priceScale
                    : amountIn * priceScale / price;
            } else {
                // For exact in, we need to adjust amountOut by going forwards through price feeds
                amountOut = config.slippageParams.shouldReverses[i]
                    ? amountOut * priceScale / price
                    : amountOut * price / priceScale;
            }
        }

        uint256 tokenInDecimals = IERC20Metadata(swapParams.tokenIn).decimals();
        uint256 tokenOutDecimals = IERC20Metadata(swapParams.tokenOut).decimals();

        // Scale amountIn to the correct amount of decimals and apply a slippage tolerance to it
        if (swapParams.isExactOut) {
            amountIn = _scaleDecimals(amountIn, tokenOutDecimals, tokenInDecimals);
            amountIn = (amountIn * (BASE_SLIPPAGE_FACTOR + config.slippageParams.maxSlippage)) / BASE_SLIPPAGE_FACTOR;
        } else {
            amountOut = _scaleDecimals(amountOut, tokenInDecimals, tokenOutDecimals);
            amountOut = (amountOut * (BASE_SLIPPAGE_FACTOR - config.slippageParams.maxSlippage)) / BASE_SLIPPAGE_FACTOR;
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
            actualAmountIn = ISwapRouter(swapParams.uniswapRouter).exactOutput(
                ISwapRouter.ExactOutputParams({
                    path: swapParams.path,
                    recipient: swapParams.recipient,
                    deadline: swapParams.deadline,
                    amountOut: amountOut,
                    amountInMaximum: amountIn
                })
            );
            actualAmountOut = amountOut;
        } else {
            // Exact in swap
            actualAmountOut = ISwapRouter(swapParams.uniswapRouter).exactInput(
                ISwapRouter.ExactInputParams({
                    path: swapParams.path,
                    recipient: swapParams.recipient,
                    deadline: swapParams.deadline,
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
    function _scaleDecimals(uint256 amount, uint256 fromDecimals, uint256 toDecimals) internal pure returns (uint256) {
        if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals));
        } else if (fromDecimals > toDecimals) {
            return amount / (10 ** (fromDecimals - toDecimals));
        }

        return amount;
    }

    /// @notice Deterministically hash the purchase configuration
    function _hashConfig(PurchaseConfig calldata config) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                config.interval,
                abi.encodePacked(
                    config.swapParams.uniswapRouter,
                    config.swapParams.recipient,
                    config.swapParams.tokenIn,
                    config.swapParams.tokenOut,
                    config.swapParams.amount,
                    config.swapParams.isExactOut,
                    config.swapParams.deadline,
                    config.swapParams.path
                ),
                abi.encodePacked(
                    config.slippageParams.maxSlippage,
                    keccak256(abi.encodePacked(config.slippageParams.priceFeeds)),
                    keccak256(abi.encodePacked(config.slippageParams.shouldReverses))
                )
            )
        );
    }
}
