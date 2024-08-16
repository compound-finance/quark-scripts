// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";

import {RecurringPurchase} from "src/RecurringPurchase.sol";

import {YulHelper} from "./lib/YulHelper.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract RecurringPurchaseTest is Test {
    event SwapExecuted(
        address indexed sender,
        address indexed recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes path
    );

    CodeJar public codeJar;
    QuarkStateManager public stateManager;
    QuarkWallet public walletImplementation;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    bytes recurringPurchase = new YulHelper().getCode("RecurringPurchase.sol/RecurringPurchase.json");

    // Contracts address on mainnet
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    // Price feeds
    address constant ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Price is $1790.45
    address constant USDC_USD_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    constructor() {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );

        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        walletImplementation = new QuarkWallet(codeJar, stateManager);
        console.log("QuarkWallet implementation: %s", address(walletImplementation));

        aliceWallet =
            QuarkWallet(payable(new QuarkMinimalProxy(address(walletImplementation), aliceAccount, address(0))));
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    /* ===== recurring purchase tests ===== */

    function testRecurringPurchaseExactInSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingUSDC = 100_000e6;
        deal(USDC, address(aliceWallet), startingUSDC);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToSell = 3_000e6;
        // Price of ETH is $1,790.45 at the current block
        uint256 expectedAmountOutMinimum = 1.65 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToSell, isExactOut: false});

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            address(aliceWallet),
            address(aliceWallet),
            USDC,
            WETH,
            3_000e6,
            1_674_115_383_192_806_353, // 1.674 WETH
            abi.encodePacked(USDC, uint24(500), WETH)
        );
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertGt(IERC20(WETH).balanceOf(address(aliceWallet)), expectedAmountOutMinimum);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC - amountToSell);
    }

    function testRecurringPurchaseExactOutSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingUSDC = 100_000e6;
        deal(USDC, address(aliceWallet), startingUSDC);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        // Price of ETH is $1,790.45 at the current block
        uint256 expectedAmountInMaximum = 1_800e6 * 10;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToPurchase, isExactOut: true});

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            address(aliceWallet),
            address(aliceWallet),
            USDC,
            WETH,
            17_920_004_306, // 17,920 USDC
            10 ether,
            abi.encodePacked(WETH, uint24(500), USDC)
        );
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase);
        assertLt(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC);
        assertGt(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC - expectedAmountInMaximum);
    }

    // Note: We test a WETH -> USDC swap here instead of the usual USDC -> WETH swap
    function testRecurringPurchaseExactInAlternateSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingWETH = 100 ether;
        deal(WETH, address(aliceWallet), startingWETH);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToSell = 10 ether;
        // Price of ETH is $1,790.45 at the current block
        uint256 expectedAmountOutMinimum = 17_800e6;
        RecurringPurchase.SwapParams memory swapParams = RecurringPurchase.SwapParams({
            uniswapRouter: uniswapRouter,
            recipient: address(aliceWallet),
            tokenIn: WETH,
            tokenOut: USDC,
            amount: amountToSell,
            isExactOut: false,
            deadline: type(uint256).max,
            path: abi.encodePacked(WETH, uint24(500), USDC)
        });
        RecurringPurchase.SlippageParams memory slippageParams = RecurringPurchase.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldReverses: _array1(false)
        });
        RecurringPurchase.PurchaseConfig memory purchaseConfig = RecurringPurchase.PurchaseConfig({
            interval: purchaseInterval,
            swapParams: swapParams,
            slippageParams: slippageParams
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), startingWETH);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), 0e6);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            address(aliceWallet),
            address(aliceWallet),
            WETH,
            USDC,
            amountToSell,
            17_901_866_835, // 17,901.86 USDC
            abi.encodePacked(WETH, uint24(500), USDC)
        );
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), startingWETH - amountToSell);
        assertGt(IERC20(USDC).balanceOf(address(aliceWallet)), expectedAmountOutMinimum);
    }

    // Note: We test a WETH -> USDC swap here instead of the usual USDC -> WETH swap
    function testRecurringPurchaseExactOutAlternateSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingWETH = 100 ether;
        deal(WETH, address(aliceWallet), startingWETH);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 1_800e6;
        // Price of ETH is $1,790.45 at the current block
        uint256 expectedAmountInMaximum = 1.1 ether;
        RecurringPurchase.SwapParams memory swapParams = RecurringPurchase.SwapParams({
            uniswapRouter: uniswapRouter,
            recipient: address(aliceWallet),
            tokenIn: WETH,
            tokenOut: USDC,
            amount: amountToPurchase,
            isExactOut: true,
            deadline: type(uint256).max,
            path: abi.encodePacked(USDC, uint24(500), WETH)
        });
        RecurringPurchase.SlippageParams memory slippageParams = RecurringPurchase.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldReverses: _array1(false)
        });
        RecurringPurchase.PurchaseConfig memory purchaseConfig = RecurringPurchase.PurchaseConfig({
            interval: purchaseInterval,
            swapParams: swapParams,
            slippageParams: slippageParams
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), startingWETH);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), 0e6);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            address(aliceWallet),
            address(aliceWallet),
            WETH,
            USDC,
            1_005_476_123_256_214_692, // 1.005 WETH
            amountToPurchase,
            abi.encodePacked(USDC, uint24(500), WETH)
        );
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertLt(IERC20(WETH).balanceOf(address(aliceWallet)), startingWETH);
        assertGt(IERC20(WETH).balanceOf(address(aliceWallet)), startingWETH - expectedAmountInMaximum);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), amountToPurchase);
    }

    function testRecurringPurchaseCanPurchaseMultipleTimes() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToPurchase, isExactOut: true});
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring purchase for the first time
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase);

        // 2a. Cannot buy again unless time interval has passed
        vm.expectRevert(RecurringPurchase.PurchaseConditionNotMet.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        // 2b. Execute recurring purchase a second time after warping 1 day
        vm.warp(block.timestamp + purchaseInterval);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToPurchase);
    }

    function testCancelRecurringPurchase() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToPurchase, isExactOut: true});
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        QuarkWallet.QuarkOperation memory cancelOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.cancel.selector),
            ScriptType.ScriptAddress
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOp);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring purchase for the first time
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase);

        // 2. Cancel replayable transaction
        aliceWallet.executeQuarkOperation(cancelOp, v2, r2, s2);

        // 3. Replayable transaction can no longer be executed
        vm.warp(block.timestamp + purchaseInterval);
        vm.expectRevert(QuarkStateManager.NonceAlreadySet.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase);
    }

    function testRecurringPurchaseWithMultiplePriceFeeds() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingUSDC = 100_000e6;
        deal(USDC, address(aliceWallet), startingUSDC);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToSell = 3_000e6;
        uint256 expectedAmountOutMinimum = 1.65 ether;
        // We are swapping from USDC -> WETH, so the order of the price feeds should be:
        // USDC/USD -> USD/WETH (convert from USDC to USD to WETH)
        RecurringPurchase.SlippageParams memory slippageParams = RecurringPurchase.SlippageParams({
            maxSlippage: 1e17, // 1% accepted slippage
            priceFeeds: _array2(USDC_USD_PRICE_FEED, ETH_USD_PRICE_FEED),
            shouldReverses: _array2(false, true)
        });
        RecurringPurchase.PurchaseConfig memory purchaseConfig = _createPurchaseConfig({
            purchaseInterval: purchaseInterval,
            amount: amountToSell,
            isExactOut: false,
            slippageParams: slippageParams
        });
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertGt(IERC20(WETH).balanceOf(address(aliceWallet)), expectedAmountOutMinimum);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC - amountToSell);
    }

    function testRecurringPurchaseWithDifferentCalldata() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase1 = 10 ether;
        uint256 amountToPurchase2 = 5 ether;
        QuarkWallet.QuarkOperation memory op1;
        QuarkWallet.QuarkOperation memory op2;
        QuarkWallet.QuarkOperation memory cancelOp;
        // Local scope to avoid stack too deep
        {
            // Two purchase configs using the same nonce: one to purchase 10 ETH and the other to purchase 5 ETH
            RecurringPurchase.PurchaseConfig memory purchaseConfig1 =
                _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToPurchase1, isExactOut: true});
            op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
                aliceWallet,
                recurringPurchase,
                abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig1),
                ScriptType.ScriptAddress
            );
            op1.expiry = purchaseConfig1.swapParams.deadline;
            RecurringPurchase.PurchaseConfig memory purchaseConfig2 =
                _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToPurchase2, isExactOut: true});
            op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
                aliceWallet,
                recurringPurchase,
                abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig2),
                ScriptType.ScriptAddress
            );
            op2.expiry = purchaseConfig2.swapParams.deadline;
            cancelOp = new QuarkOperationHelper().newBasicOpWithCalldata(
                aliceWallet,
                recurringPurchase,
                abi.encodeWithSelector(RecurringPurchase.cancel.selector),
                ScriptType.ScriptAddress
            );
            cancelOp.expiry = op2.expiry;
        }
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);
        (uint8 v3, bytes32 r3, bytes32 s3) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOp);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1a. Execute recurring purchase order #1
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase1);

        // 1b. Execute recurring purchase order #2
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase1 + amountToPurchase2);

        // 2. Warp until next purchase period
        vm.warp(block.timestamp + purchaseInterval);

        // 3a. Execute recurring purchase order #1
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToPurchase1 + amountToPurchase2);

        // 3b. Execute recurring purchase order #2
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToPurchase1 + 2 * amountToPurchase2);

        // 4. Cancel replayable transaction
        aliceWallet.executeQuarkOperation(cancelOp, v3, r3, s3);

        // 5. Warp until next purchase period
        vm.warp(block.timestamp + purchaseInterval);

        // 6. Both recurring purchase orders can no longer be executed
        vm.expectRevert(QuarkStateManager.NonceAlreadySet.selector);
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        vm.expectRevert(QuarkStateManager.NonceAlreadySet.selector);
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToPurchase1 + 2 * amountToPurchase2);
    }

    function testRevertsForInvalidInput() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        RecurringPurchase.SlippageParams memory invalidSlippageParams1 = RecurringPurchase.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: new address[](0),
            shouldReverses: new bool[](0)
        });
        RecurringPurchase.SlippageParams memory invalidSlippageParams2 = RecurringPurchase.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: new address[](0),
            shouldReverses: new bool[](1)
        });
        RecurringPurchase.PurchaseConfig memory invalidPurchaseConfig1 = _createPurchaseConfig({
            purchaseInterval: purchaseInterval,
            amount: amountToPurchase,
            isExactOut: true,
            slippageParams: invalidSlippageParams1
        });
        RecurringPurchase.PurchaseConfig memory invalidPurchaseConfig2 = _createPurchaseConfig({
            purchaseInterval: purchaseInterval,
            amount: amountToPurchase,
            isExactOut: true,
            slippageParams: invalidSlippageParams2
        });
        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, invalidPurchaseConfig1),
            ScriptType.ScriptAddress
        );
        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, invalidPurchaseConfig2),
            ScriptType.ScriptAddress
        );
        op1.expiry = invalidPurchaseConfig1.swapParams.deadline;
        op2.expiry = invalidPurchaseConfig2.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(RecurringPurchase.InvalidInput.selector);
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);

        vm.expectRevert(RecurringPurchase.InvalidInput.selector);
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);
    }

    function testRevertsForPurchaseBeforeNextPurchasePeriod() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToPurchase, isExactOut: true});
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring purchase for the first time
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase);

        // 2. Cannot buy again unless time interval has passed
        vm.expectRevert(RecurringPurchase.PurchaseConditionNotMet.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase);
    }

    function testRevertsForExpiredQuarkOperation() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToPurchase, isExactOut: true});
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = block.timestamp - 1; // Set Quark operation expiry to always expire
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(QuarkWallet.SignatureExpired.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);
    }

    function testRevertsForExpiredUniswapParams() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            _createPurchaseConfig({purchaseInterval: purchaseInterval, amount: amountToPurchase, isExactOut: true});
        purchaseConfig.swapParams.deadline = block.timestamp - 1; // Set Uniswap deadline to always expire
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(bytes("Transaction too old"));
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);
    }

    function testRevertsWhenSlippageTooHigh() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToSell = 3_000e6;
        RecurringPurchase.SlippageParams memory slippageParams = RecurringPurchase.SlippageParams({
            maxSlippage: 0e18, // 0% accepted slippage
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldReverses: _array1(true)
        });
        RecurringPurchase.PurchaseConfig memory purchaseConfig = _createPurchaseConfig({
            purchaseInterval: purchaseInterval,
            amount: amountToSell,
            isExactOut: false,
            slippageParams: slippageParams
        });
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(bytes("Too little received"));
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);
    }

    function testRevertsWhenSlippageParamsConfiguredWrong() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToSell = 3_000e6;
        RecurringPurchase.SlippageParams memory slippageParams = RecurringPurchase.SlippageParams({
            maxSlippage: 5e17, // 5% accepted slippage
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldReverses: _array1(false) // Should be true because this is a USDC -> ETH swap
        });
        RecurringPurchase.PurchaseConfig memory purchaseConfig = _createPurchaseConfig({
            purchaseInterval: purchaseInterval,
            amount: amountToSell,
            isExactOut: false,
            slippageParams: slippageParams
        });
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(bytes("Too little received"));
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);
    }

    /* ===== helper functions ===== */

    function _array1(address address0) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = address0;
        return arr;
    }

    function _array1(bool bool0) internal pure returns (bool[] memory) {
        bool[] memory arr = new bool[](1);
        arr[0] = bool0;
        return arr;
    }

    function _array2(address address0, address address1) internal pure returns (address[] memory) {
        address[] memory arr = new address[](2);
        arr[0] = address0;
        arr[1] = address1;
        return arr;
    }

    function _array2(bool bool0, bool bool1) internal pure returns (bool[] memory) {
        bool[] memory arr = new bool[](2);
        arr[0] = bool0;
        arr[1] = bool1;
        return arr;
    }

    function _createPurchaseConfig(uint40 purchaseInterval, uint256 amount, bool isExactOut)
        internal
        view
        returns (RecurringPurchase.PurchaseConfig memory)
    {
        RecurringPurchase.SlippageParams memory slippageParams = RecurringPurchase.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldReverses: _array1(true)
        });
        return _createPurchaseConfig({
            purchaseInterval: purchaseInterval,
            amount: amount,
            isExactOut: isExactOut,
            slippageParams: slippageParams
        });
    }

    function _createPurchaseConfig(
        uint40 purchaseInterval,
        uint256 amount,
        bool isExactOut,
        RecurringPurchase.SlippageParams memory slippageParams
    ) internal view returns (RecurringPurchase.PurchaseConfig memory) {
        bytes memory swapPath;
        if (isExactOut) {
            // Exact out swap
            swapPath = abi.encodePacked(WETH, uint24(500), USDC);
        } else {
            // Exact in swap
            swapPath = abi.encodePacked(USDC, uint24(500), WETH);
        }
        RecurringPurchase.SwapParams memory swapParams = RecurringPurchase.SwapParams({
            uniswapRouter: uniswapRouter,
            recipient: address(aliceWallet),
            tokenIn: USDC,
            tokenOut: WETH,
            amount: amount,
            isExactOut: isExactOut,
            deadline: type(uint256).max,
            path: swapPath
        });
        RecurringPurchase.PurchaseConfig memory purchaseConfig = RecurringPurchase.PurchaseConfig({
            interval: purchaseInterval,
            swapParams: swapParams,
            slippageParams: slippageParams
        });
        return purchaseConfig;
    }
}