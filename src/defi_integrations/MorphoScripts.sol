
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams} from "src/interfaces/IMorpho.sol";
import {IMetaMorpho} from "src/interfaces/IMetaMorpho.sol";
import {IMorphoUniversalRewardsDistributor} from "src/interfaces/IMorphoUniversalRewardsDistributor.sol";
import {DeFiScriptErrors} from "src/lib/DeFiScriptErrors.sol";

contract MorphoVaultActions {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    function deposit(address vault, address asset, uint256 amount) external returns (uint256) {
        IERC20(asset).forceApprove(vault, amount);
        return IMetaMorpho(vault).deposit(amount, address(this));
    }

    function mint(address vault, address asset, uint256 shares) external returns (uint256 assets) {
        IERC20(asset).forceApprove(vault, type(uint256).max);
        assets = IMetaMorpho(vault).mint(shares, address(this));
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

    function repayAndWithdrawCollateral(
        address morpho,
        MarketParams memory marketParams,
        uint256 repayAmount,
        uint256 repayShares,
        uint256 withdrawAmount,
        address onBehalf,
        address receiver
    ) external {
        if (repayAmount > 0 || repayShares > 0) {
            if (repayAmount > 0) {
                IERC20(marketParams.loanToken).forceApprove(morpho, repayAmount);
                IMorpho(morpho).repay(marketParams, repayAmount, 0, onBehalf, new bytes(0));
            } else {
                IERC20(marketParams.loanToken).forceApprove(morpho, type(uint256).max);
                IMorpho(morpho).repay(marketParams, 0, repayShares, onBehalf, new bytes(0));
                IERC20(marketParams.loanToken).forceApprove(morpho, 0);
            }
        }
        if (withdrawAmount > 0) {
            IMorpho(morpho).withdrawCollateral(marketParams, withdrawAmount, onBehalf, receiver);
        }
    }

    function supplyCollateralAndBorrow(
        address morpho,
        MarketParams memory marketParams,
        uint256 supplyAssetAmount,
        uint256 borrowAssetAmount,
        address onBehalf,
        address receiver
    ) external {
        if (supplyAssetAmount > 0) {
            IERC20(marketParams.collateralToken).forceApprove(morpho, supplyAssetAmount);
            IMorpho(morpho).supplyCollateral(marketParams, supplyAssetAmount, onBehalf, new bytes(0));
        }
        if (borrowAssetAmount > 0) {
            IMorpho(morpho).borrow(marketParams, borrowAssetAmount, 0, onBehalf, receiver);
        }
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
            distributors.length != accounts.length || distributors.length != rewards.length
                || distributors.length != claimables.length || distributors.length != proofs.length
        ) {
            revert DeFiScriptErrors.InvalidInput();
        }

        for (uint256 i = 0; i < distributors.length; ++i) {
            IMorphoUniversalRewardsDistributor(distributors[i]).claim(accounts[i], rewards[i], claimables[i], proofs[i]);
        }
    }
}