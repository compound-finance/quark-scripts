// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {IMorpho, MarketParams, Position} from "src/interfaces/IMorpho.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {YulHelper} from "./lib/YulHelper.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";

import "src/MorphoScripts.sol";

/**
 * Tests for Morpho Blue market
 */
contract MorphoActionsTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant adaptiveCurveIrm = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant morphoOracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    MarketParams marketParams = MarketParams(USDC, wstETH, morphoOracle, adaptiveCurveIrm, 0.86e18);
    bytes MorphoActionsScripts = new YulHelper().getCode("MorphoScripts.sol/MorphoActions.json");

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            20564787 // 2024-08-19 12:34:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
    }

    function testBorrowOnAssetsAmount() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morpho, 10e18);
        IMorpho(morpho).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(MorphoActions.borrow.selector, morpho, marketParams, 1000e6, 0),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }

    function testBorrowOnSharesAmount() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morpho, 10e18);
        IMorpho(morpho).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(MorphoActions.borrow.selector, morpho, marketParams, 0, 1e15),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(wallet)), 1048.9e6, 1e6);
    }

    function testRepayAssetsAmount() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morpho, 10e18);
        IMorpho(morpho).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        IMorpho(morpho).borrow(marketParams, 1000e6, 0, address(wallet), address(wallet));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(MorphoActions.repay.selector, morpho, marketParams, 1000e6, 0, new bytes(0)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
        assertApproxEqAbs(
            IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares, 9.533e14, 0.1e14
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0);
        assertApproxEqAbs(IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares, 0, 0.1e14);
    }

    function testRepaySharesAmount() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);
        deal(USDC, address(wallet), 100e6);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morpho, 10e18);
        IMorpho(morpho).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        IMorpho(morpho).borrow(marketParams, 1000e6, 0, address(wallet), address(wallet));
        vm.stopPrank();

        uint256 sharesRepay = IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares;
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(MorphoActions.repay.selector, morpho, marketParams, 0e6, sharesRepay, new bytes(0)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1100e6);
        assertApproxEqAbs(
            IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares, 9.533e14, 0.1e14
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(wallet)), 100e6, 0.01e6);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares, 0);
    }

    function testSupplyCollateral() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(MorphoActions.supplyCollateral.selector, morpho, marketParams, 10e18, new bytes(0)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10e18);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).collateral, 0);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).collateral, 10e18);
    }

    function testWithdrawCollateral() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morpho, 10e18);
        IMorpho(morpho).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(MorphoActions.withdrawCollateral.selector, morpho, marketParams, 10e18),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).collateral, 10e18);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10e18);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).collateral, 0e18);
    }

    function testRepayAndWithdrawCollateral() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);
        deal(USDC, address(wallet), 100e6);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morpho, 10e18);
        IMorpho(morpho).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        IMorpho(morpho).borrow(marketParams, 1000e6, 0, address(wallet), address(wallet));
        vm.stopPrank();

        uint256 sharesRepay = IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares;
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(
                MorphoActions.repayAndWithdrawCollateral.selector, morpho, marketParams, 0, sharesRepay, 10e18
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1100e6);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0);
        assertApproxEqAbs(
            IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares, 9.533e14, 0.1e14
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(wallet)), 100e6, 0.01e6);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares, 0);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10e18);
    }

    function testSupplyCollateralAndBorrow() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(
                MorphoActions.supplyCollateralAndBorrow.selector, morpho, marketParams, 10e18, 1000e6
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10e18);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).collateral, 0);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).collateral, 10e18);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }

    function testRepayMaxAndWithdrawCollateral() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);
        deal(USDC, address(wallet), 100e6);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morpho, 10e18);
        IMorpho(morpho).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        IMorpho(morpho).borrow(marketParams, 1000e6, 0, address(wallet), address(wallet));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            MorphoActionsScripts,
            abi.encodeWithSelector(
                MorphoActions.repayAndWithdrawCollateral.selector, morpho, marketParams, type(uint256).max, 0, 10e18
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1100e6);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0);
        assertApproxEqAbs(
            IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares, 9.533e14, 0.1e14
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(wallet)), 100e6, 0.01e6);
        assertEq(IMorpho(morpho).position(marketId(marketParams), address(wallet)).borrowShares, 0);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10e18);
    }

    // Helper function to convert MarketParams to bytes32 Id
    // Reference: https://github.com/morpho-org/morpho-blue/blob/731e3f7ed97cf15f8fe00b86e4be5365eb3802ac/src/libraries/MarketParamsLib.sol
    function marketId(MarketParams memory params) public pure returns (bytes32 marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(params, 160)
        }
    }
}