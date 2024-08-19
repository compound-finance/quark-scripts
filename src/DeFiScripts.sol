// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

import {QuarkScript} from "quark-core/src/QuarkScript.sol";

import {IComet} from "./interfaces/IComet.sol";
import {ICometRewards} from "./interfaces/ICometRewards.sol";
import {IMorpho, MarketParams} from "./interfaces/IMorpho.sol";
import {IMetaMorpho} from "./interfaces/IMetaMorpho.sol";
import {IMorphoUniversalRewardsDistributor} from "./interfaces/IMorphoUniversalRewardsDistributor.sol";
import {DeFiScriptErrors} from "./lib/DeFiScriptErrors.sol";

contract CometSupplyActions {
    using SafeERC20 for IERC20;

    /**
     *   @notice Supply an asset to Comet
     *   @param comet The Comet address
     *   @param asset The asset address
     *   @param amount The amount to supply
     */
    function supply(address comet, address asset, uint256 amount) external {
        IERC20(asset).forceApprove(comet, amount);
        IComet(comet).supply(asset, amount);
    }

    /**
     * @notice Supply an asset to Comet to a specific address
     * @param comet The Comet address
     * @param to The recipient address
     * @param asset The asset address
     * @param amount The amount to supply
     */
    function supplyTo(address comet, address to, address asset, uint256 amount) external {
        IERC20(asset).forceApprove(comet, amount);
        IComet(comet).supplyTo(to, asset, amount);
    }

    /**
     *   @notice Supply an asset to Comet from one address to another address
     *   @param comet The Comet address
     *   @param from The from address
     *   @param to The to address
     *   @param asset The asset address
     *   @param amount The amount to supply
     */
    function supplyFrom(address comet, address from, address to, address asset, uint256 amount) external {
        IComet(comet).supplyFrom(from, to, asset, amount);
    }

    /**
     * @notice Supply multiple assets to Comet
     * @param comet The Comet address
     * @param assets The assets to supply
     * @param amounts The amounts of each asset to supply
     */
    function supplyMultipleAssets(address comet, address[] calldata assets, uint256[] calldata amounts) external {
        if (assets.length != amounts.length) {
            revert DeFiScriptErrors.InvalidInput();
        }

        for (uint256 i = 0; i < assets.length;) {
            IERC20(assets[i]).forceApprove(comet, amounts[i]);
            IComet(comet).supply(assets[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }
}

contract CometWithdrawActions {
    using SafeERC20 for IERC20;

    /**
     *  @notice Withdraw an asset from Comet
     *  @param comet The Comet address
     *  @param asset The asset address
     *  @param amount The amount to withdraw
     */
    function withdraw(address comet, address asset, uint256 amount) external {
        IComet(comet).withdraw(asset, amount);
    }

    /**
     * @notice Withdraw an asset from Comet to a specific address
     * @param comet The Comet address
     * @param to The recipient address
     * @param asset The asset address
     * @param amount The amount to withdraw
     */
    function withdrawTo(address comet, address to, address asset, uint256 amount) external {
        IComet(comet).withdrawTo(to, asset, amount);
    }

    /**
     *   @notice Withdraw an asset from Comet from one address to another address
     *   @param comet The Comet address
     *   @param from The from address
     *   @param to The to address
     *   @param asset The asset address
     *   @param amount The amount to withdraw
     */
    function withdrawFrom(address comet, address from, address to, address asset, uint256 amount) external {
        IComet(comet).withdrawFrom(from, to, asset, amount);
    }

    /**
     * @notice Withdraw multiple assets from Comet
     * @param comet The Comet address
     * @param assets The assets to withdraw
     * @param amounts The amounts of each asset to withdraw
     */
    function withdrawMultipleAssets(address comet, address[] calldata assets, uint256[] calldata amounts) external {
        if (assets.length != amounts.length) {
            revert DeFiScriptErrors.InvalidInput();
        }

        for (uint256 i = 0; i < assets.length;) {
            IComet(comet).withdraw(assets[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }
}

contract UniswapSwapActions {
    using SafeERC20 for IERC20;

    struct SwapParamsExactIn {
        address uniswapRouter;
        address recipient;
        address tokenFrom;
        uint256 amount;
        // Minimum amount of target token to receive (revert if return amount is less than this)
        uint256 amountOutMinimum;
        uint256 deadline;
        // Path of the swap
        bytes path;
    }

    struct SwapParamsExactOut {
        address uniswapRouter;
        address recipient;
        address tokenFrom;
        uint256 amount;
        // Maximum amount of input token to spend (revert if input amount is greater than this)
        uint256 amountInMaximum;
        uint256 deadline;
        // Path of the swap
        bytes path;
    }

    /**
     * @notice Swap token on Uniswap with Exact Input (i.e. Set input amount and swap for target token)
     * @param params SwapParamsExactIn struct
     */
    function swapAssetExactIn(SwapParamsExactIn calldata params) external {
        IERC20(params.tokenFrom).forceApprove(params.uniswapRouter, params.amount);
        ISwapRouter(params.uniswapRouter).exactInput(
            ISwapRouter.ExactInputParams({
                path: params.path,
                recipient: params.recipient,
                deadline: params.deadline,
                amountIn: params.amount,
                amountOutMinimum: params.amountOutMinimum
            })
        );
    }

    /**
     * @notice Swap token on Uniswap with Exact Output (i.e. Set output amount and swap with required amount of input token)
     * @param params SwapParamsExactOut struct
     */
    function swapAssetExactOut(SwapParamsExactOut calldata params) external {
        IERC20(params.tokenFrom).forceApprove(params.uniswapRouter, params.amountInMaximum);
        uint256 amountIn = ISwapRouter(params.uniswapRouter).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: params.path,
                recipient: params.recipient,
                deadline: params.deadline,
                amountOut: params.amount,
                amountInMaximum: params.amountInMaximum
            })
        );

        // Reset approved leftover input token back to 0, if there is any leftover approved amount
        if (amountIn < params.amountInMaximum) {
            IERC20(params.tokenFrom).forceApprove(params.uniswapRouter, 0);
        }
    }
}

contract TransferActions is QuarkScript {
    using SafeERC20 for IERC20;

    /**
     * @notice Transfer ERC20 token
     * @param token The token address
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function transferERC20Token(address token, address recipient, uint256 amount) external onlyWallet {
        IERC20(token).safeTransfer(recipient, amount);
    }

    /**
     * @notice Transfer native token (i.e. ETH)
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function transferNativeToken(address recipient, uint256 amount) external onlyWallet {
        (bool success, bytes memory data) = payable(recipient).call{value: amount}("");
        if (!success) {
            revert DeFiScriptErrors.TransferFailed(data);
        }
    }
}

contract CometClaimRewards {
    /**
     * @notice Claim rewards
     * @param cometRewards The CometRewards addresses
     * @param comets The Comet addresses
     * @param recipient The recipient address, that will receive the COMP rewards
     */
    function claim(address[] calldata cometRewards, address[] calldata comets, address recipient) external {
        if (cometRewards.length != comets.length) {
            revert DeFiScriptErrors.InvalidInput();
        }

        for (uint256 i = 0; i < cometRewards.length;) {
            ICometRewards(cometRewards[i]).claim(comets[i], recipient, true);
            unchecked {
                ++i;
            }
        }
    }
}

contract CometSupplyMultipleAssetsAndBorrow {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    function run(
        address comet,
        address[] calldata assets,
        uint256[] calldata amounts,
        address baseAsset,
        uint256 borrow
    ) external {
        if (assets.length != amounts.length) {
            revert DeFiScriptErrors.InvalidInput();
        }

        for (uint256 i = 0; i < assets.length;) {
            IERC20(assets[i]).forceApprove(comet, amounts[i]);
            IComet(comet).supply(assets[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
        IComet(comet).withdraw(baseAsset, borrow);
    }
}

contract CometRepayAndWithdrawMultipleAssets {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    function run(address comet, address[] calldata assets, uint256[] calldata amounts, address baseAsset, uint256 repay)
        external
    {
        if (assets.length != amounts.length) {
            revert DeFiScriptErrors.InvalidInput();
        }

        IERC20(baseAsset).forceApprove(comet, repay);
        IComet(comet).supply(baseAsset, repay);
        for (uint256 i = 0; i < assets.length;) {
            IComet(comet).withdraw(assets[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }
}

contract ApproveAndSwap {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    /**
     * Approve a specified contract for an amount of token and execute the data against it
     * @param to The contract address to approve execute on
     * @param sellToken The token address to approve
     * @param sellAmount The amount to approve
     * @param buyToken The token that is being bought
     * @param buyAmount The amount of the buy token to receive after the swap
     * @param data The data to execute
     */
    function run(
        address to,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount,
        bytes calldata data
    ) external {
        IERC20(sellToken).forceApprove(to, sellAmount);
        uint256 buyTokenBalanceBefore = IERC20(buyToken).balanceOf(address(this));

        (bool success, bytes memory returnData) = to.call(data);
        if (!success) {
            revert DeFiScriptErrors.ApproveAndSwapFailed(returnData);
        }

        uint256 buyTokenBalanceAfter = IERC20(buyToken).balanceOf(address(this));
        uint256 actualBuyAmount = buyTokenBalanceAfter - buyTokenBalanceBefore;
        if (actualBuyAmount < buyAmount) {
            revert DeFiScriptErrors.TooMuchSlippage(buyAmount, actualBuyAmount);
        }

        // Approvals to external contracts should always be reset to 0
        IERC20(sellToken).forceApprove(to, 0);
    }
}

// === Morpho actiosn ===
contract MorphoVaultActions {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    function deposit(address vault, address asset, uint256 amount) external returns (uint256) {
        IERC20(asset).forceApprove(vault, amount);
        return IMetaMorpho(vault).deposit(amount, address(this));
    }

    function mint(address vault, address asset, uint256 shares) external returns (uint256 assets) {
        IERC20(asset).forceApprove(vault, type(uint256).max);
        assets =  IMetaMorpho(vault).mint(shares, address(this));
        IERC20(asset).forceApprove(vault, 0);
    }

    function withdraw(address vault, uint256 amount) external returns (uint256) {
        return IMetaMorpho(vault).withdraw(amount, address(this), address(this));
    }

    function redeem(address vault, uint256 shares) external returns (uint256) {
        return IMetaMorpho(vault).redeem(shares, address(this), address(this));
    }
}

contract MorphoBlueActions {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    function borrow(
        address morpho,
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        return IMorpho(morpho).borrow(marketParams, assets, shares, onBehalf, receiver);
    }

    function repay(
        address morpho,
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        if (assets > 0) {
            IERC20(marketParams.loanToken).forceApprove(morpho, assets);
            (assetsRepaid, sharesRepaid) = IMorpho(morpho).repay(marketParams, assets, shares, onBehalf, data);
        } else {
            IERC20(marketParams.loanToken).forceApprove(morpho, type(uint256).max);
            (assetsRepaid, sharesRepaid) = IMorpho(morpho).repay(marketParams, assets, shares, onBehalf, data);
            IERC20(marketParams.loanToken).forceApprove(morpho, 0);
        }
    }

    function supplyCollateral(
        address morpho,
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes calldata data
    ) external {
        IERC20(marketParams.collateralToken).forceApprove(morpho, assets);
        IMorpho(morpho).supplyCollateral(marketParams, assets, onBehalf, data);
    }

    function withdrawCollateral(
        address morpho,
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external {
        IMorpho(morpho).withdrawCollateral(marketParams, assets, onBehalf, receiver);
    }
}

contract MorphoRewardsActions {
    function claim(address distributor, address account, address reward, uint256 claimable, bytes32[] calldata proofs)
        external
    {
        IMorphoUniversalRewardsDistributor(distributor).claim(account, reward, claimable, proofs);
    }

    function claimAll(
        address[] calldata distributors,
        address[] calldata accounts,
        address[] calldata rewards,
        uint256[] calldata claimables,
        bytes32[][] calldata proofs
    ) external {
        if (
            distributors.length != accounts.length ||
            distributors.length != rewards.length ||
            distributors.length != claimables.length ||
            distributors.length != proofs.length
        ) {
            revert DeFiScriptErrors.InvalidInput();
        }

        for (uint256 i = 0; i < distributors.length; ++i) {
            IMorphoUniversalRewardsDistributor(distributors[i]).claim(accounts[i], rewards[i], claimables[i], proofs[i]);
        }
    }
}
// ======================
