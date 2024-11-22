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
import {IStETH} from "./lib/IStETH.sol";

import "src/WrapperScripts.sol";

/**
 * Tests for supplying assets to Comet
 */
contract WrapperScriptsTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    bytes wrapperScript = new YulHelper().getCode("WrapperScripts.sol/WrapperActions.json");

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
    }

    function testWrapETH() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(address(wallet), 10 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.wrapETH.selector, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(address(wallet).balance, 10 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 0 ether);
    }

    function testWrapETHUpTo() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(address(wallet), 10 ether);
        deal(WETH, address(wallet), 7 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.wrapETHUpTo.selector, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 7 ether);
        assertEq(address(wallet).balance, 10 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 7 ether);
    }

    function testWrapETHUpToDoesNotWrapIfNotNeeded() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(address(wallet), 10 ether);
        deal(WETH, address(wallet), 10 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.wrapETHUpTo.selector, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 10 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 10 ether);
    }

    function testWrapAllETH() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(address(wallet), 10 ether);
        deal(WETH, address(wallet), 7 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.wrapAllETH.selector, WETH),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 7 ether);
        assertEq(address(wallet).balance, 10 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 17 ether);
        assertEq(address(wallet).balance, 0 ether);
    }

    function testUnwrapWETH() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(WETH, address(wallet), 10 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.unwrapWETH.selector, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 0 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(address(wallet).balance, 10 ether);
    }

    function testUnwrapWETHUpTo() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(WETH, address(wallet), 10 ether);
        deal(address(wallet), 7 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.unwrapWETHUpTo.selector, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 7 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 7 ether);
        assertEq(address(wallet).balance, 10 ether);
    }

    function testUnwrapWETHUpToDoesNotUnwrapIfNotNeeded() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(WETH, address(wallet), 10 ether);
        deal(address(wallet), 10 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.unwrapWETHUpTo.selector, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 10 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 10 ether);
    }

    function testUnwrapAllWETH() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(WETH, address(wallet), 10 ether);
        deal(address(wallet), 7 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.unwrapAllWETH.selector, WETH),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(address(wallet).balance, 7 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(address(wallet).balance, 17 ether);
    }

    function testWrapStETH() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Special balance computation in Lido, have to do regular staking action to not mess up the Lido's contract
        deal(address(wallet), 10 ether);
        vm.startPrank(address(wallet));
        // Call Lido's submit() to stake
        IStETH(stETH).submit{value: 10 ether}(address(0));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.wrapLidoStETH.selector, wstETH, stETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0 ether);
        assertApproxEqAbs(IERC20(stETH).balanceOf(address(wallet)), 10 ether, 0.01 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(stETH).balanceOf(address(wallet)), 0 ether);
        assertApproxEqAbs(IERC20(wstETH).balanceOf(address(wallet)), 8.74 ether, 0.01 ether);
    }

    function testWrapAllStETH() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Special balance computation in Lido, have to do regular staking action to not mess up the Lido's contract
        deal(address(wallet), 10 ether);
        vm.startPrank(address(wallet));
        // Call Lido's submit() to stake
        IStETH(stETH).submit{value: 10 ether}(address(0));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.wrapAllLidoStETH.selector, wstETH, stETH),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0 ether);
        assertApproxEqAbs(IERC20(stETH).balanceOf(address(wallet)), 10 ether, 0.01 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        // Due to shares math in wstETH, the user can be left with a tiny amount of stETH
        assertApproxEqAbs(IERC20(stETH).balanceOf(address(wallet)), 0 ether, 1);
        assertApproxEqAbs(IERC20(wstETH).balanceOf(address(wallet)), 8.74 ether, 0.01 ether);
    }

    function testUnwrapWstETH() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.unwrapLidoWstETH.selector, wstETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(stETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertApproxEqAbs(IERC20(stETH).balanceOf(address(wallet)), 11.44 ether, 0.01 ether);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0 ether);
    }

    function testUnwrapAllWstETH() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            wrapperScript,
            abi.encodeWithSelector(WrapperActions.unwrapAllLidoWstETH.selector, wstETH),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(stETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10 ether);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertApproxEqAbs(IERC20(stETH).balanceOf(address(wallet)), 11.44 ether, 0.01 ether);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0 ether);
    }
}
