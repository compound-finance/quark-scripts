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

import {DeFiScriptErrors} from "src/lib/DeFiScriptErrors.sol";

import "src/DeFiScripts.sol";

/**
 * Tests for Morpho Blue market
 */
contract MorphoBlueActionsTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant morphoBlue = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant adaptiveCurveIrm = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant morphoOracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    MarketParams marketParams = MarketParams(USDC, wstETH, morphoOracle, adaptiveCurveIrm, 0.86e18);
    bytes morphoBlueActionsScripts = new YulHelper().getCode("DeFiScripts.sol/MorphoBlueActions.json");

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
        IERC20(wstETH).approve(morphoBlue, 10e18);
        IMorpho(morphoBlue).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            morphoBlueActionsScripts,
            abi.encodeWithSelector(
                MorphoBlueActions.borrow.selector, morphoBlue, marketParams, 1000e6, 0, address(wallet), address(wallet)
            ),
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
        IERC20(wstETH).approve(morphoBlue, 10e18);
        IMorpho(morphoBlue).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            morphoBlueActionsScripts,
            abi.encodeWithSelector(
                MorphoBlueActions.borrow.selector, morphoBlue, marketParams, 0, 1e15, address(wallet), address(wallet)
            ),
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
        IERC20(wstETH).approve(morphoBlue, 10e18);
        IMorpho(morphoBlue).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        IMorpho(morphoBlue).borrow(marketParams, 1000e6, 0, address(wallet), address(wallet));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            morphoBlueActionsScripts,
            abi.encodeWithSelector(
                MorphoBlueActions.repay.selector, morphoBlue, marketParams, 1000e6, 0, address(wallet), new bytes(0)
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
        assertApproxEqAbs(
            IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).borrowShares, 9.533e14, 0.1e14
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0);
        assertApproxEqAbs(IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).borrowShares, 0, 0.1e14);
    }

    function testRepaySharesAmount() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);
        deal(USDC, address(wallet), 100e6);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morphoBlue, 10e18);
        IMorpho(morphoBlue).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        IMorpho(morphoBlue).borrow(marketParams, 1000e6, 0, address(wallet), address(wallet));
        vm.stopPrank();

        uint256 sharesRepay = IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).borrowShares;
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            morphoBlueActionsScripts,
            abi.encodeWithSelector(
                MorphoBlueActions.repay.selector,
                morphoBlue,
                marketParams,
                0e6,
                sharesRepay,
                address(wallet),
                new bytes(0)
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1100e6);
        assertApproxEqAbs(
            IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).borrowShares, 9.533e14, 0.1e14
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(wallet)), 100e6, 0.01e6);
        assertEq(IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).borrowShares, 0);
    }

    function testSupplyCollateral() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            morphoBlueActionsScripts,
            abi.encodeWithSelector(
                MorphoBlueActions.supplyCollateral.selector,
                morphoBlue,
                marketParams,
                10e18,
                address(wallet),
                new bytes(0)
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10e18);
        assertEq(IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).collateral, 0);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0);
        assertEq(IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).collateral, 10e18);
    }

    function testWithdrawCollateral() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(wstETH, address(wallet), 10e18);

        vm.startPrank(address(wallet));
        IERC20(wstETH).approve(morphoBlue, 10e18);
        IMorpho(morphoBlue).supplyCollateral(marketParams, 10e18, address(wallet), new bytes(0));
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            morphoBlueActionsScripts,
            abi.encodeWithSelector(
                MorphoBlueActions.withdrawCollateral.selector,
                morphoBlue,
                marketParams,
                10e18,
                address(wallet),
                address(wallet)
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 0);
        assertEq(IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).collateral, 10e18);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(wstETH).balanceOf(address(wallet)), 10e18);
        assertEq(IMorpho(morphoBlue).position(marketId(marketParams), address(wallet)).collateral, 0e18);
    }

    // Helper function to convert MarketParams to bytes32 Id
    // Reference: https://github.com/morpho-org/morpho-blue/blob/731e3f7ed97cf15f8fe00b86e4be5365eb3802ac/src/libraries/MarketParamsLib.sol
    function marketId(MarketParams memory params) public pure returns (bytes32 marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(params, 160)
        }
    }
}
