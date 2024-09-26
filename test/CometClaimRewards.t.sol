// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {YulHelper} from "./lib/YulHelper.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";

import "src/DeFiScripts.sol";

/**
 * Tests for claiming COMP rewards
 */
contract CometClaimRewardsTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant cometReward = 0x1B0e765F6224C21223AeA2af16c1C46E38885a40;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
    }

    function testClaimComp() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        bytes memory cometClaimRewardsScript = new YulHelper().getCode("DeFiScripts.sol/CometClaimRewards.json");

        deal(USDC, address(wallet), 1_000_000e6);

        vm.startPrank(address(wallet));
        IERC20(USDC).approve(comet, 1_000_000e6);
        IComet(comet).supply(USDC, 1_000_000e6);
        vm.stopPrank();

        // Fastforward 180 days block to accrue COMP
        vm.warp(block.timestamp + 180 days);

        address[] memory comets = new address[](1);
        comets[0] = comet;

        address[] memory cometRewards = new address[](1);
        cometRewards[0] = cometReward;

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            cometClaimRewardsScript,
            abi.encodeCall(CometClaimRewards.claim, (cometRewards, comets, address(wallet))),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(COMP).balanceOf(address(wallet)), 0e6);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertGt(IERC20(COMP).balanceOf(address(wallet)), 0e6);
    }
}
