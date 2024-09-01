// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams, Position} from "src/interfaces/IMorpho.sol";
import {IMetaMorpho} from "src/interfaces/IMetaMorpho.sol";
import {IMorphoUniversalRewardsDistributor} from "src/interfaces/IMorphoUniversalRewardsDistributor.sol";
import {DeFiScriptErrors} from "src/lib/DeFiScriptErrors.sol";

contract MorphoVaultActions {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    /**
     * @notice Deposit assets into a MetaMorpho vault
     * @param vault The address of the MetaMorpho vault
     * @param asset The address of the asset to deposit
     * @param amount The amount of the asset to deposit
     * @return shares The amount of shares minted
     */
    function deposit(address vault, address asset, uint256 amount) external returns (uint256) {
        IERC20(asset).forceApprove(vault, amount);
        return IMetaMorpho(vault).deposit({assets: amount, receiver: address(this)});
    }

    /**
     * @notice Mint shares from a MetaMorpho vault
     * @param vault The address of the MetaMorpho vault
     * @param asset The address of the asset to mint
     * @param shares The amount of shares to mint
     * @return assets The amount of assets for shares
     */
    function mint(address vault, address asset, uint256 shares) external returns (uint256 assets) {
        IERC20(asset).forceApprove(vault, type(uint256).max);
        assets = IMetaMorpho(vault).mint({shares: shares, receiver: address(this)});
        IERC20(asset).forceApprove(vault, 0);
    }

    /**
     * @notice Withdraw assets from a MetaMorpho vault
     * @param vault The address of the MetaMorpho vault
     * @param amount The amount of assets to withdraw
     * @return shares The amount of shares burned
     */
    function withdraw(address vault, uint256 amount) external returns (uint256) {
        return IMetaMorpho(vault).withdraw({assets: amount, receiver: address(this), owner: address(this)});
    }

    /**
     * @notice Redeem shares from a MetaMorpho vault
     * @param vault The address of the MetaMorpho vault
     * @param shares The amount of shares to redeem
     * @return assets The amount of assets redeemed
     */
    function redeem(address vault, uint256 shares) external returns (uint256) {
        return IMetaMorpho(vault).redeem({shares: shares, receiver: address(this), owner: address(this)});
    }

    /**
     * @notice Redeem all shares from a MetaMorpho vault
     * As suggested from MetaMorpho.sol doc, it is recommended to not use their
     * redeemMax function to retrieve max shares to redeem due to cost.
     * Instead will just use balanceOf(vault) to optimistically redeem all shares.
     * @param vault The address of the MetaMorpho vault
     */
    function redeemAll(address vault) external returns (uint256) {
        return IMetaMorpho(vault).redeem({
            shares: IMetaMorpho(vault).balanceOf(address(this)),
            receiver: address(this),
            owner: address(this)
        });
    }
}

contract MorphoActions {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    /**
     * @notice Borrow assets or shares from a Morpho blue market on behalf of `onBehalf` and send assets to `receiver`
     * @param morpho The address of the top level Morpho contract
     * @param marketParams The market parameters of the individual morpho blue market to borrow assets from
     * @param assets The amount of assets to borrow
     * @param shares The amount of shares to borrow
     * @return assetsBorrowed The amount of assets borrowed
     * @return sharesBorrowed The amount of shares minted
     */
    function borrow(address morpho, MarketParams memory marketParams, uint256 assets, uint256 shares)
        external
        returns (uint256, uint256)
    {
        return IMorpho(morpho).borrow({
            marketParams: marketParams,
            assets: assets,
            shares: shares,
            onBehalf: address(this),
            receiver: address(this)
        });
    }

    /**
     * @notice Repay assets or shares in a Morpho blue market on behalf of `onBehalf`
     * @param morpho The address of the top level Morpho contract
     * @param marketParams The market parameters of the individual morpho blue market
     * @param assets The amount of assets to repay
     * @param shares The amount of shares to repay
     * @param data Arbitrary data to pass to the `onMorphoRepay` callback. Pass empty data if not needed
     * @return assetsRepaid The amount of assets repaid
     * @return sharesRepaid The amount of shares burned
     */
    function repay(
        address morpho,
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        bytes calldata data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        if (assets > 0) {
            IERC20(marketParams.loanToken).forceApprove(morpho, assets);
            (assetsRepaid, sharesRepaid) = IMorpho(morpho).repay({
                marketParams: marketParams,
                assets: assets,
                shares: shares,
                onBehalf: address(this),
                data: data
            });
        } else {
            IERC20(marketParams.loanToken).forceApprove(morpho, type(uint256).max);
            (assetsRepaid, sharesRepaid) = IMorpho(morpho).repay({
                marketParams: marketParams,
                assets: assets,
                shares: shares,
                onBehalf: address(this),
                data: data
            });
            IERC20(marketParams.loanToken).forceApprove(morpho, 0);
        }
    }

    /**
     * @notice Supply collateral to a Morpho blue market on behalf of `onBehalf`
     * @param morpho The address of the top level Morpho contract
     * @param marketParams The market parameters of the individual morpho blue market
     * @param assets The amount of assets to supply as collateral
     * @param data Arbitrary data to pass to the `onMorphoSupplyCollateral` callback. Pass empty data if not needed
     */
    function supplyCollateral(address morpho, MarketParams memory marketParams, uint256 assets, bytes calldata data)
        external
    {
        IERC20(marketParams.collateralToken).forceApprove(morpho, assets);
        IMorpho(morpho).supplyCollateral({
            marketParams: marketParams,
            assets: assets,
            onBehalf: address(this),
            data: data
        });
    }

    /**
     * @notice Withdraw collateral from a Morpho blue market on behalf of `onBehalf` to `receiver`
     * @param morpho The address of the top level Morpho contract
     * @param marketParams The market parameters of the individual morpho blue market
     * @param assets The amount of assets to withdraw as collateral
     */
    function withdrawCollateral(address morpho, MarketParams memory marketParams, uint256 assets) external {
        IMorpho(morpho).withdrawCollateral({
            marketParams: marketParams,
            assets: assets,
            onBehalf: address(this),
            receiver: address(this)
        });
    }

    /**
     * @notice Repay assets and withdraw collateral from a Morpho blue market on behalf of `onBehalf` and send collateral to `receiver`
     * @param morpho The address of the top level Morpho contract
     * @param marketParams The market parameters of the individual morpho blue market
     * @param repayAmount The amount of assets to repay, pass in `type(uint256).max` to repay max
     * @param repayShares The amount of shares to repay
     * @param withdrawAmount The amount of assets to withdraw as collateral
     */
    function repayAndWithdrawCollateral(
        address morpho,
        MarketParams memory marketParams,
        uint256 repayAmount,
        uint256 repayShares,
        uint256 withdrawAmount
    ) external {
        if (repayAmount > 0 || repayShares > 0) {
            if (repayAmount == type(uint256).max) {
                // Repay max
                IERC20(marketParams.loanToken).forceApprove(morpho, type(uint256).max);
                IMorpho(morpho).repay({
                    marketParams: marketParams,
                    assets: 0,
                    shares: IMorpho(morpho).position(marketId(marketParams), address(this)).borrowShares,
                    onBehalf: address(this),
                    data: new bytes(0)
                });
                IERC20(marketParams.loanToken).forceApprove(morpho, 0);
            } else if (repayAmount > 0) {
                IERC20(marketParams.loanToken).forceApprove(morpho, repayAmount);
                IMorpho(morpho).repay({
                    marketParams: marketParams,
                    assets: repayAmount,
                    shares: 0,
                    onBehalf: address(this),
                    data: new bytes(0)
                });
            } else {
                IERC20(marketParams.loanToken).forceApprove(morpho, type(uint256).max);
                IMorpho(morpho).repay({
                    marketParams: marketParams,
                    assets: 0,
                    shares: repayShares,
                    onBehalf: address(this),
                    data: new bytes(0)
                });
                IERC20(marketParams.loanToken).forceApprove(morpho, 0);
            }
        }
        if (withdrawAmount > 0) {
            IMorpho(morpho).withdrawCollateral({
                marketParams: marketParams,
                assets: withdrawAmount,
                onBehalf: address(this),
                receiver: address(this)
            });
        }
    }

    /**
     * @notice Supply collateral and borrow assets from a Morpho blue market on behalf of `onBehalf` and send borrowed assets to `receiver`
     * @param morpho The address of the top level Morpho contract
     * @param marketParams The market parameters of the individual morpho blue market
     * @param supplyAssetAmount The amount of assets to supply as collateral
     * @param borrowAssetAmount The amount of assets to borrow
     */
    function supplyCollateralAndBorrow(
        address morpho,
        MarketParams memory marketParams,
        uint256 supplyAssetAmount,
        uint256 borrowAssetAmount
    ) external {
        if (supplyAssetAmount > 0) {
            IERC20(marketParams.collateralToken).forceApprove(morpho, supplyAssetAmount);
            IMorpho(morpho).supplyCollateral({
                marketParams: marketParams,
                assets: supplyAssetAmount,
                onBehalf: address(this),
                data: new bytes(0)
            });
        }
        if (borrowAssetAmount > 0) {
            IMorpho(morpho).borrow({
                marketParams: marketParams,
                assets: borrowAssetAmount,
                shares: 0,
                onBehalf: address(this),
                receiver: address(this)
            });
        }
    }

    // Helper function to convert MarketParams to bytes32 Id
    // Reference: https://github.com/morpho-org/morpho-blue/blob/731e3f7ed97cf15f8fe00b86e4be5365eb3802ac/src/libraries/MarketParamsLib.sol
    function marketId(MarketParams memory params) public pure returns (bytes32 marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(params, 160)
        }
    }
}

contract MorphoRewardsActions {
    /**
     * @notice Claim rewards from a Morpho Universal Rewards Distributor
     * @param distributor The address of the Morpho Universal Rewards Distributor
     * @param account The address of the account to claim rewards for
     * @param reward The address of the reward token to claim
     * @param claimable The amount of rewards to claim
     * @param proofs The proofs to claim the rewards (reference: https://docs.morpho.org/rewards/tutorials/claim-rewards/)
     */
    function claim(address distributor, address account, address reward, uint256 claimable, bytes32[] calldata proofs)
        external
    {
        IMorphoUniversalRewardsDistributor(distributor).claim(account, reward, claimable, proofs);
    }

    /**
     * @notice Claim rewards from multiple Morpho Universal Rewards Distributors in one transaction
     * @param distributors The addresses of the Morpho Universal Rewards Distributors
     * @param accounts The addresses of the accounts to claim rewards for
     * @param rewards The addresses of the reward tokens to claim
     * @param claimables The amounts of rewards to claim
     * @param proofs The batch of proofs to claim the rewards (reference: https://docs.morpho.org/rewards/tutorials/claim-rewards/)
     */
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
