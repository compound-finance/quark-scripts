// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";
import {Multicall} from "quark-core-scripts/src/Multicall.sol";

import {
    CometSupplyActions,
    CometWithdrawActions,
    UniswapSwapActions,
    TransferActions,
    CometClaimRewards,
    CometSupplyMultipleAssetsAndBorrow,
    CometRepayAndWithdrawMultipleAssets
} from "src/DeFiScripts.sol";

// Deploy with:
// $ set -a && source .env && ./script/deploy.sh --broadcast

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK
// QUARK_WALLET_FACTORY_ADDRESS

// Optional ENV vars:
// ETHERSCAN_KEY

contract DeployQuarkScripts is Script {
    CodeJar codeJar;
    Ethcall ethcall;
    Multicall multicall;
    CometSupplyActions cometSupplyActions;
    CometWithdrawActions cometWithdrawActions;
    UniswapSwapActions uniswapSwapActions;
    TransferActions transferActions;
    CometClaimRewards cometClaimRewards;
    CometSupplyMultipleAssetsAndBorrow cometSupplyMultipleAssetsAndBorrow;
    CometRepayAndWithdrawMultipleAssets cometRepayAndWithdrawMultipleAssets;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        codeJar = CodeJar(vm.envAddress("CODE_JAR"));
        console.log("Code Jar Address: ", address(codeJar));

        vm.startBroadcast(deployer);

        console.log("=============================================================");
        console.log("Deploying Core Scripts");

        ethcall = Ethcall(codeJar.saveCode(abi.encodePacked(type(Ethcall).creationCode)));
        console.log("Ethcall Deployed:", address(ethcall));

        multicall = Multicall(codeJar.saveCode(abi.encodePacked(type(Multicall).creationCode)));
        console.log("Multicall Deployed:", address(multicall));

        console.log("Deploying Quark Scripts");

        cometSupplyActions =
            CometSupplyActions(codeJar.saveCode(abi.encodePacked(type(CometSupplyActions).creationCode)));
        console.log("CometSupplyActions Deployed:", address(cometSupplyActions));

        cometWithdrawActions =
            CometWithdrawActions(codeJar.saveCode(abi.encodePacked(type(CometWithdrawActions).creationCode)));
        console.log("CometWithdrawActions Deployed:", address(cometWithdrawActions));

        uniswapSwapActions =
            UniswapSwapActions(codeJar.saveCode(abi.encodePacked(type(UniswapSwapActions).creationCode)));
        console.log("UniswapSwapActions Deployed:", address(uniswapSwapActions));

        transferActions = TransferActions(codeJar.saveCode(abi.encodePacked(type(TransferActions).creationCode)));
        console.log("TransferActions Deployed:", address(transferActions));

        cometClaimRewards = CometClaimRewards(codeJar.saveCode(abi.encodePacked(type(CometClaimRewards).creationCode)));
        console.log("CometClaimRewards Deployed:", address(cometClaimRewards));

        cometSupplyMultipleAssetsAndBorrow = CometSupplyMultipleAssetsAndBorrow(
            codeJar.saveCode(abi.encodePacked(type(CometSupplyMultipleAssetsAndBorrow).creationCode))
        );
        console.log("CometSupplyMultipleAssetsAndBorrow Deployed:", address(cometSupplyMultipleAssetsAndBorrow));

        cometRepayAndWithdrawMultipleAssets = CometRepayAndWithdrawMultipleAssets(
            codeJar.saveCode(abi.encodePacked(type(CometRepayAndWithdrawMultipleAssets).creationCode))
        );
        console.log("CometRepayAndWithdrawMultipleAssets Deployed:", address(cometRepayAndWithdrawMultipleAssets));

        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
