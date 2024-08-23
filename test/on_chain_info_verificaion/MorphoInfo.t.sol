// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

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
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            20580267 // 2024-08-21 16:27:00 PST
        );

        verifyKnownMarketsParams(1);
        verifyKnownVaults(1);
    }

    function testBaseMainnet() public {
        // Fork setup to get on-chain on base mainnet
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/base-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18746757 // 2024-08-21 16:27:00 PST
        );

        verifyKnownMarketsParams(8453);
        verifyKnownVaults(8453);
    }

    function testEthSepolia() public {
        // Fork setup to get on-chain on base sepolia
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-sepolia/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            6546096 // 2024-08-21 16:27:00 PST
        );

        verifyKnownMarketsParams(11155111);
        verifyKnownVaults(11155111);
    }

    function testBaseSepolia() public {
        // Fork setup to get on-chain on base sepolia
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/base-sepolia/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
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
                    IMorpho(MorphoInfo.getMorphoAddress()).market(marketId(marketParams));
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

    // Helper function to convert MarketParams to bytes32 Id
    // Reference: https://github.com/morpho-org/morpho-blue/blob/731e3f7ed97cf15f8fe00b86e4be5365eb3802ac/src/libraries/MarketParamsLib.sol
    function marketId(MarketParams memory params) public pure returns (bytes32) {
        return keccak256(abi.encode(params));
    }
}