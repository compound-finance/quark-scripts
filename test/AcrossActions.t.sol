// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {YulHelper} from "./lib/YulHelper.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";

import {DeFiScriptErrors} from "src/lib/DeFiScriptErrors.sol";

import {AcrossActions} from "src/AcrossScripts.sol";

/**
 * Tests for bridging assets using Across
 */
contract AcrossActionsTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contract addresses on mainnet (unless otherwise specified)
    address constant ACROSS_SPOKE_POOL = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;

    bytes acrossActionsScript = new YulHelper().getCode("AcrossScripts.sol/AcrossActions.json");

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            20564787 // 2024-08-19 12:34:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
    }

    function testDepositV3WithERC20() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(USDC_MAINNET, address(wallet), 1_000e6);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            acrossActionsScript,
            abi.encodeCall(
                AcrossActions.depositV3,
                (
                    ACROSS_SPOKE_POOL, // spokePool
                    address(wallet), // depositor
                    address(wallet), // recipient
                    USDC_MAINNET, // inputToken
                    USDC_BASE, // outputToken
                    100e6, // inputAmount
                    99.9e6, // outputAmount
                    8453, // destinationChainId
                    address(0), // exclusiveRelayer
                    uint32(block.timestamp), // quoteTimestamp
                    uint32(block.timestamp), // fillDeadline
                    0, // exclusivityDeadline
                    new bytes(0), // message
                    false // useNativeToken
                )
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(wallet)), 1_000e6);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(wallet)), 900e6);
    }

    function testDepositV3WithNativeToken() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(address(wallet), 100e18);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            acrossActionsScript,
            abi.encodeCall(
                AcrossActions.depositV3,
                (
                    ACROSS_SPOKE_POOL, // spokePool
                    address(wallet), // depositor
                    address(wallet), // recipient
                    WETH_MAINNET, // inputToken
                    WETH_BASE, // outputToken
                    10e18, // inputAmount
                    9.99e18, // outputAmount
                    8453, // destinationChainId
                    address(0), // exclusiveRelayer
                    uint32(block.timestamp), // quoteTimestamp
                    uint32(block.timestamp), // fillDeadline
                    0, // exclusivityDeadline
                    new bytes(0), // message
                    true // useNativeToken
                )
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(address(wallet).balance, 100e18);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(address(wallet).balance, 90e18);
    }

    function testDepositV3RevertsIfInputTokenIsNotWrappedNativeToken() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(address(wallet), 100e18);
        deal(USDC_MAINNET, address(wallet), 1_000e6);

        // useNativeToken is set to true, but the inputToken is not WETH
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            acrossActionsScript,
            abi.encodeCall(
                AcrossActions.depositV3,
                (
                    ACROSS_SPOKE_POOL, // spokePool
                    address(wallet), // depositor
                    address(wallet), // recipient
                    USDC_MAINNET, // inputToken
                    USDC_BASE, // outputToken
                    100e6, // inputAmount
                    99.9e6, // outputAmount
                    8453, // destinationChainId
                    address(0), // exclusiveRelayer
                    uint32(block.timestamp), // quoteTimestamp
                    uint32(block.timestamp), // fillDeadline
                    0, // exclusivityDeadline
                    new bytes(0), // message
                    true // useNativeToken
                )
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSignature("MsgValueDoesNotMatchInputAmount()"));
        wallet.executeQuarkOperation(op, signature);
    }

    function testDepositV3RevertsIfNotEnoughInputToken() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(USDC_MAINNET, address(wallet), 99e6);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            acrossActionsScript,
            abi.encodeCall(
                AcrossActions.depositV3,
                (
                    ACROSS_SPOKE_POOL, // spokePool
                    address(wallet), // depositor
                    address(wallet), // recipient
                    USDC_MAINNET, // inputToken
                    USDC_BASE, // outputToken
                    100e6, // inputAmount
                    99.9e6, // outputAmount
                    8453, // destinationChainId
                    address(0), // exclusiveRelayer
                    uint32(block.timestamp), // quoteTimestamp
                    uint32(block.timestamp), // fillDeadline
                    0, // exclusivityDeadline
                    new bytes(0), // message
                    false // useNativeToken
                )
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        wallet.executeQuarkOperation(op, signature);
    }

    function testDepositV3RevertsIfInvalidQuoteTimestamp() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(USDC_MAINNET, address(wallet), 1_000e6);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            acrossActionsScript,
            abi.encodeCall(
                AcrossActions.depositV3,
                (
                    ACROSS_SPOKE_POOL, // spokePool
                    address(wallet), // depositor
                    address(wallet), // recipient
                    USDC_MAINNET, // inputToken
                    USDC_BASE, // outputToken
                    100e6, // inputAmount
                    99.9e6, // outputAmount
                    8453, // destinationChainId
                    address(0), // exclusiveRelayer
                    uint32(block.timestamp - 1_000_000), // quoteTimestamp
                    uint32(block.timestamp), // fillDeadline
                    0, // exclusivityDeadline
                    new bytes(0), // message
                    false // useNativeToken
                )
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSignature("InvalidQuoteTimestamp()"));
        wallet.executeQuarkOperation(op, signature);
    }

    function testDepositV3RevertsIfInvalidFillDeadline() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(USDC_MAINNET, address(wallet), 1_000e6);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            acrossActionsScript,
            abi.encodeCall(
                AcrossActions.depositV3,
                (
                    ACROSS_SPOKE_POOL, // spokePool
                    address(wallet), // depositor
                    address(wallet), // recipient
                    USDC_MAINNET, // inputToken
                    USDC_BASE, // outputToken
                    100e6, // inputAmount
                    99.9e6, // outputAmount
                    8453, // destinationChainId
                    address(0), // exclusiveRelayer
                    uint32(block.timestamp), // quoteTimestamp
                    uint32(block.timestamp - 10), // fillDeadline
                    0, // exclusivityDeadline
                    new bytes(0), // message
                    false // useNativeToken
                )
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSignature("InvalidFillDeadline()"));
        wallet.executeQuarkOperation(op, signature);
    }
}
