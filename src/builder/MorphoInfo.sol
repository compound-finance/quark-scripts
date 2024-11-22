// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {MarketParams} from "src/interfaces/IMorpho.sol";
import {HashMap} from "./HashMap.sol";

library MorphoInfo {
    error UnsupportedChainId();
    error MorphoMarketNotFound();
    error MorphoVaultNotFound();

    // Note: Current Morpho has same address across mainnet and base
    function getMorphoAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1 || chainId == 8453 || chainId == 84532) {
            return 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
        } else if (chainId == 11155111) {
            return 0xd011EE229E7459ba1ddd22631eF7bF528d424A14;
        } else {
            revert UnsupportedChainId();
        }
    }

    // Morpho blue markets
    // Note: This is a simple key, as one market per chain per borrow asset per collateral asset
    struct MorphoMarketKey {
        uint256 chainId;
        string borrowAssetSymbol;
        string collateralAssetSymbol;
    }

    function getKnownMorphoMarketsParams() internal pure returns (HashMap.Map memory) {
        HashMap.Map memory knownMarkets = HashMap.newMap();
        // === Mainnet morpho markets ===
        // cbBTC collateral markets
        // Reference: https://linear.app/legend-labs/project/morpho-borrow-78f58156ed93/overview
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "USDC", collateralAssetSymbol: "cbBTC"}),
            MarketParams({
                loanToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                collateralToken: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,
                oracle: 0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        // WBTC collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "USDC", collateralAssetSymbol: "WBTC"}),
            MarketParams({
                loanToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                collateralToken: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                oracle: 0xDddd770BADd886dF3864029e4B377B5F6a2B6b83,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "USDT", collateralAssetSymbol: "WBTC"}),
            MarketParams({
                loanToken: 0xdAC17F958D2ee523a2206206994597C13D831ec7,
                collateralToken: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                oracle: 0x008bF4B1cDA0cc9f0e882E0697f036667652E1ef,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "WETH", collateralAssetSymbol: "WBTC"}),
            MarketParams({
                loanToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                collateralToken: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                oracle: 0xc29B3Bc033640baE31ca53F8a0Eb892AdF68e663,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.915e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "PYUSD", collateralAssetSymbol: "WBTC"}),
            MarketParams({
                loanToken: 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8,
                collateralToken: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                oracle: 0xc53c90d6E9A5B69E4ABf3d5Ae4c79225C7FeF3d2,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "eUSD", collateralAssetSymbol: "WBTC"}),
            MarketParams({
                loanToken: 0xA0d69E286B938e21CBf7E51D71F6A4c8918f482F,
                collateralToken: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                oracle: 0x032F1C64899b2C89835E51aCeD9434b0aDEaA69d,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "USDA", collateralAssetSymbol: "WBTC"}),
            MarketParams({
                loanToken: 0x0000206329b97DB379d5E1Bf586BbDB969C63274,
                collateralToken: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                oracle: 0x032F1C64899b2C89835E51aCeD9434b0aDEaA69d,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        // wstETH collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "WETH", collateralAssetSymbol: "wstETH"}),
            MarketParams({
                loanToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                oracle: 0xbD60A6770b27E084E8617335ddE769241B0e71D8,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.945e18
            })
        );
        // Reference: https://linear.app/legend-labs/project/morpho-borrow-78f58156ed93/overview
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "USDC", collateralAssetSymbol: "wstETH"}),
            MarketParams({
                loanToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                oracle: 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "USDC", collateralAssetSymbol: "wstETH"}),
            MarketParams({
                loanToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                oracle: 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "USDT", collateralAssetSymbol: "wstETH"}),
            MarketParams({
                loanToken: 0xdAC17F958D2ee523a2206206994597C13D831ec7,
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                oracle: 0x95DB30fAb9A3754e42423000DF27732CB2396992,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "eUSD", collateralAssetSymbol: "wstETH"}),
            MarketParams({
                loanToken: 0xA0d69E286B938e21CBf7E51D71F6A4c8918f482F,
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                oracle: 0xBC693693fDBB177Ad05ff38633110016BC043AC5,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "PYUSD", collateralAssetSymbol: "wstETH"}),
            MarketParams({
                loanToken: 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8,
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                oracle: 0x27679a17b7419fB10Bd9D143f21407760fdA5C53,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        // weETH collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "WETH", collateralAssetSymbol: "weETH"}),
            MarketParams({
                loanToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                collateralToken: 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee,
                oracle: 0x3fa58b74e9a8eA8768eb33c8453e9C2Ed089A40a,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        // MKR collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "USDC", collateralAssetSymbol: "MKR"}),
            MarketParams({
                loanToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                collateralToken: 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2,
                oracle: 0x6686788B4315A4F93d822c1Bf73910556FCe2d5a,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.77e18
            })
        );
        // USDe collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "DAI", collateralAssetSymbol: "USDe"}),
            MarketParams({
                loanToken: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
                collateralToken: 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3,
                oracle: 0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        // sUSDe collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 1, borrowAssetSymbol: "DAI", collateralAssetSymbol: "sUSDe"}),
            MarketParams({
                loanToken: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
                collateralToken: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
                oracle: 0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25,
                irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
                lltv: 0.86e18
            })
        );
        // === Base morpho markets ===
        // cbBTC collateral markets
        // Reference: https://linear.app/legend-labs/project/morpho-borrow-78f58156ed93/overview
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 8453, borrowAssetSymbol: "USDC", collateralAssetSymbol: "cbBTC"}),
            MarketParams({
                loanToken: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                collateralToken: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,
                oracle: 0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9,
                irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
                lltv: 0.86e18
            })
        );
        // WETH collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 8453, borrowAssetSymbol: "USDC", collateralAssetSymbol: "WETH"}),
            MarketParams({
                loanToken: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                collateralToken: 0x4200000000000000000000000000000000000006,
                oracle: 0xFEa2D58cEfCb9fcb597723c6bAE66fFE4193aFE4,
                irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
                lltv: 0.86e18
            })
        );
        // wstETH collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 8453, borrowAssetSymbol: "WETH", collateralAssetSymbol: "wstETH"}),
            MarketParams({
                loanToken: 0x4200000000000000000000000000000000000006,
                collateralToken: 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452,
                oracle: 0x4A11590e5326138B514E08A9B52202D42077Ca65,
                irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
                lltv: 0.945e18
            })
        );
        // cbETH collateral markets
        // Reference: https://linear.app/legend-labs/project/morpho-borrow-78f58156ed93/overview
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 8453, borrowAssetSymbol: "USDC", collateralAssetSymbol: "cbETH"}),
            MarketParams({
                loanToken: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                collateralToken: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22,
                oracle: 0xb40d93F44411D8C09aD17d7F88195eF9b05cCD96,
                irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
                lltv: 0.86e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 8453, borrowAssetSymbol: "WETH", collateralAssetSymbol: "cbETH"}),
            MarketParams({
                loanToken: 0x4200000000000000000000000000000000000006,
                collateralToken: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22,
                oracle: 0xB03855Ad5AFD6B8db8091DD5551CAC4ed621d9E6,
                irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
                lltv: 0.945e18
            })
        );
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 8453, borrowAssetSymbol: "eUSD", collateralAssetSymbol: "cbETH"}),
            MarketParams({
                loanToken: 0xCfA3Ef56d303AE4fAabA0592388F19d7C3399FB4,
                collateralToken: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22,
                oracle: 0xc3Fa71D77d80f671F366DAA6812C8bD6C7749cEc,
                irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
                lltv: 0.86e18
            })
        );
        // ezETH collateral markets
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 8453, borrowAssetSymbol: "WETH", collateralAssetSymbol: "ezETH"}),
            MarketParams({
                loanToken: 0x4200000000000000000000000000000000000006,
                collateralToken: 0x2416092f143378750bb29b79eD961ab195CcEea5,
                oracle: 0xcca88a97dE6700Bb5DAdf4082Cf35A55F383AF05,
                irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
                lltv: 0.915e18
            })
        );

        // === Sepolia testnet morpho markets ===
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 11155111, borrowAssetSymbol: "USDC", collateralAssetSymbol: "WETH"}),
            MarketParams({
                loanToken: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
                collateralToken: 0x2D5ee574e710219a521449679A4A7f2B43f046ad,
                oracle: 0xaF02D46ADA7bae6180Ac2034C897a44Ac11397b2,
                irm: 0x8C5dDCD3F601c91D1BF51c8ec26066010ACAbA7c,
                lltv: 945000000000000000
            })
        );

        // === Base Sepolia testnet morpho markets ===
        addMarketParams(
            knownMarkets,
            MorphoMarketKey({chainId: 84532, borrowAssetSymbol: "USDC", collateralAssetSymbol: "WETH"}),
            MarketParams({
                loanToken: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
                collateralToken: 0x4200000000000000000000000000000000000006,
                oracle: 0x1631366C38d49ba58793A5F219050923fbF24C81,
                irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
                lltv: 0.915e18
            })
        );

        return knownMarkets;
    }

    function getMarketParams(uint256 chainId, string memory collateralAssetSymbol, string memory borrowAssetSymbol)
        internal
        pure
        returns (MarketParams memory)
    {
        HashMap.Map memory knownMarkets = getKnownMorphoMarketsParams();
        return getMarketParams(
            knownMarkets,
            MorphoMarketKey({
                chainId: chainId,
                borrowAssetSymbol: borrowAssetSymbol,
                collateralAssetSymbol: collateralAssetSymbol
            })
        );
    }

    // Morpho vaults
    // Note: Potentially can add other key (i.e. curator) for supporting multiple vaults with same assets
    struct MorphoVaultKey {
        uint256 chainId;
        string supplyAssetSymbol;
    }

    function getKnownMorphoVaultsAddresses() internal pure returns (HashMap.Map memory) {
        HashMap.Map memory knownVaults = HashMap.newMap();
        // === Mainnet morpho vaults ===
        // USDC (Gauntlet USDC Core)
        addMorphoVaultAddress(
            knownVaults,
            MorphoVaultKey({chainId: 1, supplyAssetSymbol: "USDC"}),
            0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458
        );
        // USDT (Gaunlet USDT Prime)
        addMorphoVaultAddress(
            knownVaults,
            MorphoVaultKey({chainId: 1, supplyAssetSymbol: "USDT"}),
            0x8CB3649114051cA5119141a34C200D65dc0Faa73
        );
        // WETH (Gauntlet WETH Core)
        addMorphoVaultAddress(
            knownVaults,
            MorphoVaultKey({chainId: 1, supplyAssetSymbol: "WETH"}),
            0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658
        );
        // WBTC (Guantlet WBTC Core)
        addMorphoVaultAddress(
            knownVaults,
            MorphoVaultKey({chainId: 1, supplyAssetSymbol: "WBTC"}),
            0x443df5eEE3196e9b2Dd77CaBd3eA76C3dee8f9b2
        );

        // === Base morpho vaults ===
        // USDC (Moonwell Flaghship USDC)
        addMorphoVaultAddress(
            knownVaults,
            MorphoVaultKey({chainId: 8453, supplyAssetSymbol: "USDC"}),
            0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca
        );
        // WETH (Moonwell Flaghship ETH)
        addMorphoVaultAddress(
            knownVaults,
            MorphoVaultKey({chainId: 8453, supplyAssetSymbol: "WETH"}),
            0xa0E430870c4604CcfC7B38Ca7845B1FF653D0ff1
        );

        // === Sepolia testnet morpho vaults ===
        // USDC (Legend USDC)
        addMorphoVaultAddress(
            knownVaults,
            MorphoVaultKey({chainId: 11155111, supplyAssetSymbol: "USDC"}),
            0x62559B2707013890FBB111280d2aE099a2EFc342
        );

        // === Base Sepolia testnet morpho vaults ===
        // None

        return knownVaults;
    }

    function getMorphoVaultAddress(uint256 chainId, string memory supplyAssetSymbol) internal pure returns (address) {
        HashMap.Map memory knownVaults = getKnownMorphoVaultsAddresses();
        return
            getMorphoVaultAddress(knownVaults, MorphoVaultKey({chainId: chainId, supplyAssetSymbol: supplyAssetSymbol}));
    }

    // Helpers for map
    function addMorphoVaultAddress(HashMap.Map memory knownVaults, MorphoVaultKey memory key, address addr)
        internal
        pure
    {
        HashMap.put(knownVaults, abi.encode(key), abi.encode(addr));
    }

    function getMorphoVaultAddress(HashMap.Map memory knownVaults, MorphoVaultKey memory key)
        internal
        pure
        returns (address)
    {
        if (!HashMap.contains(knownVaults, abi.encode(key))) {
            revert MorphoVaultNotFound();
        }
        return abi.decode(HashMap.get(knownVaults, abi.encode(key)), (address));
    }

    function addMarketParams(HashMap.Map memory knownMarkets, MorphoMarketKey memory key, MarketParams memory params)
        internal
        pure
    {
        HashMap.put(knownMarkets, abi.encode(key), abi.encode(params));
    }

    function getMarketParams(HashMap.Map memory knownMarkets, MorphoMarketKey memory key)
        internal
        pure
        returns (MarketParams memory)
    {
        if (!HashMap.contains(knownMarkets, abi.encode(key))) {
            revert MorphoMarketNotFound();
        }
        return abi.decode(HashMap.get(knownMarkets, abi.encode(key)), (MarketParams));
    }

    // Helper function to convert MarketParams to bytes32 Id
    // Reference: https://github.com/morpho-org/morpho-blue/blob/731e3f7ed97cf15f8fe00b86e4be5365eb3802ac/src/libraries/MarketParamsLib.sol
    function marketId(MarketParams memory params) internal pure returns (bytes32) {
        return keccak256(abi.encode(params));
    }
}
