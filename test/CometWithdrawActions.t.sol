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

import {DeFiScriptErrors} from "src/lib/DeFiScriptErrors.sol";
import "src/DeFiScripts.sol";

/**
 * Tests for withdrawing assets from Comet
 */
contract WithdrawActionsTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    bytes cometWithdrawScript = new YulHelper().getCode("DeFiScripts.sol/CometWithdrawActions.json");

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
    }

    function testWithdraw() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        deal(WETH, address(wallet), 10 ether);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        vm.stopPrank();

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            cometWithdrawScript,
            abi.encodeWithSelector(CometWithdrawActions.withdraw.selector, comet, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
    }

    function testWithdrawTo() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        QuarkWallet wallet2 = QuarkWallet(factory.create(alice, address(wallet), bytes32("2")));
        deal(WETH, address(wallet), 10 ether);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        vm.stopPrank();

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet2)), 0 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            cometWithdrawScript,
            abi.encodeWithSelector(CometWithdrawActions.withdrawTo.selector, comet, address(wallet2), WETH, 10 ether),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet2)), 10 ether);
    }

    function testWithdrawFrom() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        QuarkWallet wallet2 = QuarkWallet(factory.create(alice, address(wallet), bytes32("2")));
        deal(WETH, address(wallet2), 10 ether);

        vm.startPrank(address(wallet2));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        IComet(comet).allow(address(wallet), true);
        vm.stopPrank();

        assertEq(IComet(comet).collateralBalanceOf(address(wallet2), WETH), 10 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            cometWithdrawScript,
            abi.encodeWithSelector(
                CometWithdrawActions.withdrawFrom.selector, comet, address(wallet2), address(wallet), WETH, 10 ether
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IComet(comet).collateralBalanceOf(address(wallet2), WETH), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
    }

    function testBorrow() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        deal(WETH, address(wallet), 10 ether);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            cometWithdrawScript,
            abi.encodeWithSelector(CometWithdrawActions.withdraw.selector, comet, USDC, 100e6),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0e6);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 0e6);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 100e6);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 100e6);
    }

    function testWithdrawMultipleAssets() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(WETH, address(wallet), 10 ether);
        deal(LINK, address(wallet), 1000e18);
        deal(USDC, address(wallet), 1000e6);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        IERC20(LINK).approve(comet, 1000e18);
        IComet(comet).supply(LINK, 1000e18);
        IERC20(USDC).approve(comet, 1000e6);
        IComet(comet).supply(USDC, 1000e6);
        vm.stopPrank();

        // Fast forward 1 hour to accrue some interest so we can withdraw the full 1000e6 of SUDC
        skip(3600);

        address[] memory assets = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        assets[0] = WETH;
        assets[1] = LINK;
        assets[2] = USDC;
        amounts[0] = 10 ether;
        amounts[1] = 1000e18;
        amounts[2] = 1000e6;

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            cometWithdrawScript,
            abi.encodeWithSelector(CometWithdrawActions.withdrawMultipleAssets.selector, comet, assets, amounts),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), LINK), 1000e18);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IERC20(LINK).balanceOf(address(wallet)), 0e18);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0e6);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), LINK), 0e18);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IERC20(LINK).balanceOf(address(wallet)), 1000e18);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }

    function testInvalidInput() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        address[] memory assets = new address[](3);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = WETH;
        assets[1] = LINK;
        assets[2] = USDC;
        amounts[0] = 10 ether;

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            cometWithdrawScript,
            abi.encodeWithSelector(CometWithdrawActions.withdrawMultipleAssets.selector, comet, assets, amounts),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.expectRevert(abi.encodeWithSelector(DeFiScriptErrors.InvalidInput.selector));
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);
    }
}
