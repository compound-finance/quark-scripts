// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {HashMap} from "src/builder/HashMap.sol";
import {IMorpho, MarketParams} from "src/interfaces/IMorpho.sol";
import {IMetaMorpho} from "src/interfaces/IMetaMorpho.sol";
import {MorphoInfo} from "src/builder/MorphoInfo.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";

/**
 * Verify the MorphoInfo info is correct on-chain
 */
contract MorphoInfoTest is Test {
    function testEthMainnet() public {
        // Fork setup to get on-chain on eth mainnet
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            21145787 // 2024-11-08 14:04:00 PST
        );

        verifyKnownMarketsParams(1);
        verifyKnownVaults(1);
    }

    function testBaseMainnet() public {
        // Fork setup to get on-chain on base mainnet
        vm.createSelectFork(
            vm.envString("BASE_MAINNET_RPC_URL"),
            22156966 // 2024-11-08 14:00:00 PST
        );

        verifyKnownMarketsParams(8453);
        verifyKnownVaults(8453);
    }

    function testEthSepolia() public {
        // Fork setup to get on-chain on base sepolia
        vm.createSelectFork(
            vm.envString("SEPOLIA_RPC_URL"),
            7038811 // 2024-11-08 14:10:00 PST
        );

        verifyKnownMarketsParams(11155111);
        verifyKnownVaults(11155111);
    }

    function testBaseSepolia() public {
        // Fork setup to get on-chain on base sepolia
        vm.createSelectFork(
            vm.envString("BASE_SEPOLIA_RPC_URL"),
            14257289 // 2024-08-21 16:27:00 PST
        );

        verifyKnownMarketsParams(84532);
        verifyKnownVaults(84532);
    }

    function verifyKnownMarketsParams(uint256 chainId) internal {
        HashMap.Map memory markets = MorphoInfo.getKnownMorphoMarketsParams();
        bytes[] memory keys = HashMap.keys(markets);
        MorphoInfo.MorphoMarketKey[] memory marketKeys = new MorphoInfo.MorphoMarketKey[](keys.length);
        for (uint256 i = 0; i < keys.length; ++i) {
            marketKeys[i] = abi.decode(keys[i], (MorphoInfo.MorphoMarketKey));
        }

        // Filter and verify
        for (uint256 i = 0; i < marketKeys.length; ++i) {
            if (marketKeys[i].chainId == chainId) {
                MarketParams memory marketParams = MorphoInfo.getMarketParams(markets, marketKeys[i]);
                (uint128 totalSupplyAssets,,,, uint128 lastUpdate,) =
                    IMorpho(MorphoInfo.getMorphoAddress(chainId)).market(MorphoInfo.marketId(marketParams));
                assertGt(
                    totalSupplyAssets,
                    0,
                    "MorphoInfo has markets with NO liquidity, something is wrong and may impact user expereince"
                );
                assertGt(lastUpdate, 0, "MorphoInfo has markets with NO lastUpdate, the market is never used");
            }
        }
    }

    function verifyKnownVaults(uint256 chainId) internal {
        HashMap.Map memory vaults = MorphoInfo.getKnownMorphoVaultsAddresses();
        bytes[] memory keys = HashMap.keys(vaults);
        MorphoInfo.MorphoVaultKey[] memory vaultKeys = new MorphoInfo.MorphoVaultKey[](keys.length);
        for (uint256 i = 0; i < keys.length; ++i) {
            vaultKeys[i] = abi.decode(keys[i], (MorphoInfo.MorphoVaultKey));
        }

        // Filter and verify
        for (uint256 i = 0; i < vaultKeys.length; ++i) {
            if (vaultKeys[i].chainId == chainId) {
                address vault = MorphoInfo.getMorphoVaultAddress(vaults, vaultKeys[i]);
                assertGt(
                    IERC4626(vault).totalAssets(),
                    0,
                    "MorphoInfo has vaults with NO assets, empty vault may impact user expereince"
                );
            }
        }
    }
}
