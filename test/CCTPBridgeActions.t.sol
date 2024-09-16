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

import "src/BridgeScripts.sol";

/**
 * Tests for CCTP Bridge
 */
contract CCTPBridge is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant tokenMessenger = 0xBd3fa81B58Ba92a82136038B25aDec7066af3155;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Domain value for the CCTP bridge, DIFFERENT from chain id
    uint32 constant mainnetDomain = 0;
    uint32 constant baseDomain = 6;

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
    }

    function testBridgeToBase() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        bytes memory cctpBridgeScript = new YulHelper().getCode("BridgeScripts.sol/CCTPBridgeActions.json");

        deal(USDC, address(wallet), 1_000_000e6);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            cctpBridgeScript,
            abi.encodeCall(
                CCTPBridgeActions.bridgeUSDC,
                (tokenMessenger, 500_000e6, 6, bytes32(uint256(uint160(address(wallet)))), USDC)
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1_000_000e6);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 500_000e6);
    }
}
