// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";

import {Cancel} from "src/Cancel.sol";
import {RecurringSwap} from "src/RecurringSwap.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import {AggregatorV3Interface} from "src/vendor/chainlink/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract RecurringSwapTest is Test {
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
    QuarkNonceManager public nonceManager;
    QuarkWallet public walletImplementation;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    MockPriceFeed mockPriceFeed;

    bytes recurringSwap = new YulHelper().getCode("RecurringSwap.sol/RecurringSwap.json");

    // Contracts address on mainnet
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    // Uniswap SwapRouter02 info on mainnet
    address constant UNISWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    // Price feeds
    address constant ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Price is $1790.45
    address constant USDC_USD_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    // Swap window params
    uint256 constant SWAP_WINDOW_INTERVAL = 1 days;
    uint256 constant SWAP_WINDOW_LENGTH = 1 days;

    constructor() {
        // Fork setup
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            18429607 // 2023-10-25 13:24:00 PST
        );

        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));

        walletImplementation = new QuarkWallet(codeJar, nonceManager);
        console.log("QuarkWallet implementation: %s", address(walletImplementation));

        aliceWallet =
            QuarkWallet(payable(new QuarkMinimalProxy(address(walletImplementation), aliceAccount, address(0))));
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));

        mockPriceFeed = new MockPriceFeed();
    }

    /* ===== recurring swap tests ===== */

    function testRecurringSwapExactInSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingUSDC = 100_000e6;
        deal(USDC, address(aliceWallet), startingUSDC);
        uint256 amountToSell = 3_000e6;
        // Price of ETH is $1,790.45 at the current block
        uint256 expectedAmountOutMinimum = 1.65 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSell,
            isExactOut: false
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

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
        aliceWallet.executeQuarkOperation(op, signature1);

        assertGt(IERC20(WETH).balanceOf(address(aliceWallet)), expectedAmountOutMinimum);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC - amountToSell);
    }

    function testRecurringSwapExactOutSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingUSDC = 100_000e6;
        deal(USDC, address(aliceWallet), startingUSDC);
        uint256 amountToSwap = 10 ether;
        // Price of ETH is $1,790.45 at the current block
        uint256 expectedAmountInMaximum = 1_800e6 * 10;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

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
        aliceWallet.executeQuarkOperation(op, signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap);
        assertLt(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC);
        assertGt(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC - expectedAmountInMaximum);
    }

    // Note: We test a WETH -> USDC swap here instead of the usual USDC -> WETH swap
    function testRecurringSwapExactInAlternateSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingWETH = 100 ether;
        deal(WETH, address(aliceWallet), startingWETH);
        uint256 amountToSell = 10 ether;
        // Price of ETH is $1,790.45 at the current block
        uint256 expectedAmountOutMinimum = 17_800e6;
        RecurringSwap.SwapWindow memory swapWindow = RecurringSwap.SwapWindow({
            startTime: block.timestamp,
            interval: SWAP_WINDOW_INTERVAL,
            length: SWAP_WINDOW_LENGTH
        });
        RecurringSwap.SwapParams memory swapParams = RecurringSwap.SwapParams({
            uniswapRouter: UNISWAP_ROUTER,
            recipient: address(aliceWallet),
            tokenIn: WETH,
            tokenOut: USDC,
            amount: amountToSell,
            isExactOut: false,
            path: abi.encodePacked(WETH, uint24(500), USDC)
        });
        RecurringSwap.SlippageParams memory slippageParams = RecurringSwap.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldInvert: _array1(false)
        });
        RecurringSwap.SwapConfig memory swapConfig =
            RecurringSwap.SwapConfig({swapWindow: swapWindow, swapParams: swapParams, slippageParams: slippageParams});

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

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
        aliceWallet.executeQuarkOperation(op, signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), startingWETH - amountToSell);
        assertGt(IERC20(USDC).balanceOf(address(aliceWallet)), expectedAmountOutMinimum);
    }

    // Note: We test a WETH -> USDC swap here instead of the usual USDC -> WETH swap
    function testRecurringSwapExactOutAlternateSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingWETH = 100 ether;
        deal(WETH, address(aliceWallet), startingWETH);
        uint256 amountToSwap = 1_800e6;
        // Price of ETH is $1,790.45 at the current block
        uint256 expectedAmountInMaximum = 1.1 ether;
        RecurringSwap.SwapWindow memory swapWindow = RecurringSwap.SwapWindow({
            startTime: block.timestamp,
            interval: SWAP_WINDOW_INTERVAL,
            length: SWAP_WINDOW_LENGTH
        });
        RecurringSwap.SwapParams memory swapParams = RecurringSwap.SwapParams({
            uniswapRouter: UNISWAP_ROUTER,
            recipient: address(aliceWallet),
            tokenIn: WETH,
            tokenOut: USDC,
            amount: amountToSwap,
            isExactOut: true,
            path: abi.encodePacked(USDC, uint24(500), WETH)
        });
        RecurringSwap.SlippageParams memory slippageParams = RecurringSwap.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldInvert: _array1(false)
        });
        RecurringSwap.SwapConfig memory swapConfig =
            RecurringSwap.SwapConfig({swapWindow: swapWindow, swapParams: swapParams, slippageParams: slippageParams});

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

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
            amountToSwap,
            abi.encodePacked(USDC, uint24(500), WETH)
        );
        aliceWallet.executeQuarkOperation(op, signature1);

        assertLt(IERC20(WETH).balanceOf(address(aliceWallet)), startingWETH);
        assertGt(IERC20(WETH).balanceOf(address(aliceWallet)), startingWETH - expectedAmountInMaximum);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), amountToSwap);
    }

    function testRecurringSwapCanSwapMultipleTimes() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        // Set up mock price feed so prices aren't stale after warping
        (, int256 price,,,) = AggregatorV3Interface(ETH_USD_PRICE_FEED).latestRoundData();
        mockPriceFeed.setLatestAnswer(price, block.timestamp);

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfigWithMockPriceFeed({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress,
            1
        );
        op.expiry = type(uint256).max;
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring swap for the first time
        aliceWallet.executeQuarkOperation(op, signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap);

        // 2a. Cannot buy again unless time interval has passed
        vm.expectRevert(
            abi.encodeWithSelector(
                RecurringSwap.SwapWindowNotOpen.selector,
                block.timestamp + SWAP_WINDOW_INTERVAL,
                SWAP_WINDOW_LENGTH,
                block.timestamp
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature1);

        // 2b. Execute recurring swap a second time after warping 1 day
        vm.warp(block.timestamp + SWAP_WINDOW_INTERVAL);
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToSwap);
    }

    function testCancelRecurringSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress,
            2
        );
        op.expiry = type(uint256).max;
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        QuarkWallet.QuarkOperation memory cancelOp = new QuarkOperationHelper().cancelReplayableByNop(aliceWallet, op);
        cancelOp.nonce = op.nonce;
        bytes memory signature2 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOp);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring swap for the first time
        aliceWallet.executeQuarkOperation(op, signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap);

        // 2. Cancel replayable transaction
        aliceWallet.executeQuarkOperationWithSubmissionToken(cancelOp, submissionTokens[1], signature2);

        // 3. Replayable transaction can no longer be executed
        vm.warp(block.timestamp + SWAP_WINDOW_INTERVAL);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(aliceWallet), op.nonce, submissionTokens[1]
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature1);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(aliceWallet), op.nonce, submissionTokens[2]
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[2], signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap);
    }

    function testRecurringSwapWithMultiplePriceFeeds() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingUSDC = 100_000e6;
        deal(USDC, address(aliceWallet), startingUSDC);
        uint256 amountToSell = 3_000e6;
        uint256 expectedAmountOutMinimum = 1.65 ether;
        // We are swapping from USDC -> WETH, so the order of the price feeds should be:
        // USDC/USD -> USD/WETH (convert from USDC to USD to WETH)
        RecurringSwap.SlippageParams memory slippageParams = RecurringSwap.SlippageParams({
            maxSlippage: 1e17, // 1% accepted slippage
            priceFeeds: _array2(USDC_USD_PRICE_FEED, ETH_USD_PRICE_FEED),
            shouldInvert: _array2(false, true)
        });
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSell,
            isExactOut: false,
            slippageParams: slippageParams
        });
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, signature1);

        assertGt(IERC20(WETH).balanceOf(address(aliceWallet)), expectedAmountOutMinimum);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC - amountToSell);
    }

    function testRecurringSwapWithDifferentCalldata() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        // Set up mock price feed so prices aren't stale after warping
        (, int256 price,,,) = AggregatorV3Interface(ETH_USD_PRICE_FEED).latestRoundData();
        mockPriceFeed.setLatestAnswer(price, block.timestamp);

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap1 = 10 ether;
        uint256 amountToSwap2 = 5 ether;
        bytes32[] memory submissionTokens;
        QuarkWallet.QuarkOperation memory op1;
        QuarkWallet.QuarkOperation memory op2;
        QuarkWallet.QuarkOperation memory cancelOp;
        // Local scope to avoid stack too deep
        {
            // Two swap configs using the same nonce: one to swap 10 ETH and the other to swap 5 ETH
            RecurringSwap.SwapConfig memory swapConfig1 = _createSwapConfigWithMockPriceFeed({
                startTime: block.timestamp,
                swapInterval: SWAP_WINDOW_INTERVAL,
                swapLength: SWAP_WINDOW_LENGTH,
                amount: amountToSwap1,
                isExactOut: true
            });
            (op1, submissionTokens) = new QuarkOperationHelper().newReplayableOpWithCalldata(
                aliceWallet,
                recurringSwap,
                abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig1),
                ScriptType.ScriptAddress,
                5
            );
            op1.expiry = type(uint256).max;
            RecurringSwap.SwapConfig memory swapConfig2 = _createSwapConfigWithMockPriceFeed({
                startTime: block.timestamp,
                swapInterval: SWAP_WINDOW_INTERVAL,
                swapLength: SWAP_WINDOW_LENGTH,
                amount: amountToSwap2,
                isExactOut: true
            });
            op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
                aliceWallet,
                recurringSwap,
                abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig2),
                ScriptType.ScriptAddress
            );
            op2.expiry = type(uint256).max;
            op2.nonce = op1.nonce;
            op2.isReplayable = true;
            cancelOp = new QuarkOperationHelper().cancelReplayableByNop(aliceWallet, op1);
            cancelOp.expiry = type(uint256).max;
            cancelOp.nonce = op1.nonce;
        }
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);
        bytes memory signature2 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);
        bytes memory signature3 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOp);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1a. Execute recurring swap order #1
        aliceWallet.executeQuarkOperation(op1, signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap1);

        // 1b. Execute recurring swap order #2
        aliceWallet.executeQuarkOperationWithSubmissionToken(op2, submissionTokens[1], signature2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap1 + amountToSwap2);

        // 2. Warp until next swap period
        vm.warp(block.timestamp + SWAP_WINDOW_INTERVAL);

        // 3a. Execute recurring swap order #1
        aliceWallet.executeQuarkOperationWithSubmissionToken(op1, submissionTokens[2], signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToSwap1 + amountToSwap2);

        // 3b. Execute recurring swap order #2
        aliceWallet.executeQuarkOperationWithSubmissionToken(op2, submissionTokens[3], signature2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToSwap1 + 2 * amountToSwap2);

        // 4. Cancel replayable transaction
        aliceWallet.executeQuarkOperationWithSubmissionToken(cancelOp, submissionTokens[4], signature3);

        // 5. Warp until next swap period
        vm.warp(block.timestamp + SWAP_WINDOW_INTERVAL);

        // 6. Both recurring swap orders can no longer be executed
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(aliceWallet), op1.nonce, submissionTokens[4]
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op1, submissionTokens[4], signature1);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(aliceWallet), op2.nonce, submissionTokens[5]
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op2, submissionTokens[5], signature2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToSwap1 + 2 * amountToSwap2);
    }

    function testRecurringSwapCannotSwapMultipleTimesForMissedWindows() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        // Set up mock price feed so prices aren't stale after warping
        (, int256 price,,,) = AggregatorV3Interface(ETH_USD_PRICE_FEED).latestRoundData();
        mockPriceFeed.setLatestAnswer(price, block.timestamp);

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfigWithMockPriceFeed({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress,
            2
        );
        op.expiry = type(uint256).max;
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring swap for the first time
        aliceWallet.executeQuarkOperation(op, signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap);

        // 2. Skip a few swap intervals by warping past multiple swap intervals
        mockPriceFeed.setLatestAnswer(price, block.timestamp + 10 * SWAP_WINDOW_INTERVAL);
        vm.warp(block.timestamp + 10 * SWAP_WINDOW_INTERVAL);

        // 3. Execute recurring swap a second time
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToSwap);

        // 4. Cannot buy again at the current timestamp even though we skipped a few swap intervals
        vm.expectRevert(
            abi.encodeWithSelector(
                RecurringSwap.SwapWindowNotOpen.selector,
                block.timestamp + SWAP_WINDOW_INTERVAL,
                SWAP_WINDOW_LENGTH,
                block.timestamp
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[2], signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToSwap);
    }

    function testRevertsForInvalidInput() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 amountToSwap = 10 ether;
        RecurringSwap.SlippageParams memory invalidSlippageParams1 = RecurringSwap.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: new address[](0),
            shouldInvert: new bool[](0)
        });
        RecurringSwap.SlippageParams memory invalidSlippageParams2 = RecurringSwap.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: new address[](0),
            shouldInvert: new bool[](1)
        });
        RecurringSwap.SwapConfig memory invalidSwapConfig1 = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true,
            slippageParams: invalidSlippageParams1
        });
        RecurringSwap.SwapConfig memory invalidSwapConfig2 = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true,
            slippageParams: invalidSlippageParams2
        });
        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, invalidSwapConfig1),
            ScriptType.ScriptAddress
        );
        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, invalidSwapConfig2),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);
        bytes memory signature2 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(RecurringSwap.InvalidInput.selector);
        aliceWallet.executeQuarkOperation(op1, signature1);

        vm.expectRevert(RecurringSwap.InvalidInput.selector);
        aliceWallet.executeQuarkOperation(op2, signature2);
    }

    function testRevertsForSwapBeforeNextSwapWindow() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress,
            1
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring swap for the first time
        aliceWallet.executeQuarkOperation(op, signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap);

        // 2. Cannot buy again unless time interval has passed
        vm.expectRevert(
            abi.encodeWithSelector(
                RecurringSwap.SwapWindowNotOpen.selector,
                block.timestamp + SWAP_WINDOW_INTERVAL,
                SWAP_WINDOW_LENGTH,
                block.timestamp
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap);
    }

    function testRevertsForSwapWhenSwapWindowIsClosed() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        // Set up mock price feed so prices aren't stale after warping
        (, int256 price,,,) = AggregatorV3Interface(ETH_USD_PRICE_FEED).latestRoundData();
        mockPriceFeed.setLatestAnswer(price, block.timestamp);

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        uint256 windowLength = 30;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfigWithMockPriceFeed({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: windowLength,
            amount: amountToSwap,
            isExactOut: true
        });
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress,
            2
        );
        op.expiry = type(uint256).max;
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring swap for the first time
        aliceWallet.executeQuarkOperation(op, signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToSwap);

        // 2. Warp a window into the future and execute a second swap
        vm.warp(block.timestamp + SWAP_WINDOW_INTERVAL);
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToSwap);

        // 3. Warp more than a window into the future and fail to execute a third swap
        vm.warp(block.timestamp + SWAP_WINDOW_INTERVAL + windowLength + 1);
        uint256 lastWindowStart = block.timestamp - windowLength - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                RecurringSwap.SwapWindowClosed.selector, lastWindowStart, windowLength, block.timestamp
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[2], signature1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 2 * amountToSwap);
    }

    function testRevertsForSwapBeforeStartTime() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp + 100,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.expectRevert(
            abi.encodeWithSelector(
                RecurringSwap.SwapWindowNotOpen.selector, block.timestamp + 100, SWAP_WINDOW_LENGTH, block.timestamp
            )
        );
        aliceWallet.executeQuarkOperation(op, signature1);
    }

    function testRevertsForExpiredQuarkOperation() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = block.timestamp - 1; // Set Quark operation expiry to always expire
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(QuarkWallet.SignatureExpired.selector);
        aliceWallet.executeQuarkOperation(op, signature1);
    }

    function testRevertsWhenSlippageTooHigh() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSell = 3_000e6;
        RecurringSwap.SlippageParams memory slippageParams = RecurringSwap.SlippageParams({
            maxSlippage: 0e18, // 0% accepted slippage
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldInvert: _array1(true)
        });
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSell,
            isExactOut: false,
            slippageParams: slippageParams
        });
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(bytes("Too little received"));
        aliceWallet.executeQuarkOperation(op, signature1);
    }

    function testRevertsWhenSlippageParamsConfiguredWrong() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSell = 3_000e6;
        RecurringSwap.SlippageParams memory slippageParams = RecurringSwap.SlippageParams({
            maxSlippage: 5e17, // 5% accepted slippage
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldInvert: _array1(false) // Should be true because this is a USDC -> ETH swap
        });
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfig({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSell,
            isExactOut: false,
            slippageParams: slippageParams
        });
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress
        );
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(bytes("Too little received"));
        aliceWallet.executeQuarkOperation(op, signature1);
    }

    function testRevertsForBadPrice() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        // Set up mock price feed with bad price
        mockPriceFeed.setLatestAnswer(0, block.timestamp);

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfigWithMockPriceFeed({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress,
            2
        );
        op.expiry = type(uint256).max;
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(RecurringSwap.BadPrice.selector, address(mockPriceFeed)));
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[0], signature1);
    }

    function testRevertsForStalePrice() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        // Set up mock price feed with stale price
        (, int256 price,,,) = AggregatorV3Interface(ETH_USD_PRICE_FEED).latestRoundData();
        mockPriceFeed.setLatestAnswer(price, block.timestamp - 86_401);

        deal(USDC, address(aliceWallet), 100_000e6);
        uint256 amountToSwap = 10 ether;
        RecurringSwap.SwapConfig memory swapConfig = _createSwapConfigWithMockPriceFeed({
            startTime: block.timestamp,
            swapInterval: SWAP_WINDOW_INTERVAL,
            swapLength: SWAP_WINDOW_LENGTH,
            amount: amountToSwap,
            isExactOut: true
        });
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            recurringSwap,
            abi.encodeWithSelector(RecurringSwap.swap.selector, swapConfig),
            ScriptType.ScriptAddress,
            2
        );
        op.expiry = type(uint256).max;
        bytes memory signature1 = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(RecurringSwap.StalePrice.selector, address(mockPriceFeed), 86_401));
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[0], signature1);
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

    function _createSwapConfigWithMockPriceFeed(
        uint256 startTime,
        uint256 swapInterval,
        uint256 swapLength,
        uint256 amount,
        bool isExactOut
    ) internal view returns (RecurringSwap.SwapConfig memory) {
        RecurringSwap.SlippageParams memory slippageParams = RecurringSwap.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: _array1(address(mockPriceFeed)),
            shouldInvert: _array1(true)
        });
        return _createSwapConfig({
            startTime: startTime,
            swapInterval: swapInterval,
            swapLength: swapLength,
            amount: amount,
            isExactOut: isExactOut,
            slippageParams: slippageParams
        });
    }

    function _createSwapConfig(
        uint256 startTime,
        uint256 swapInterval,
        uint256 swapLength,
        uint256 amount,
        bool isExactOut
    ) internal view returns (RecurringSwap.SwapConfig memory) {
        RecurringSwap.SlippageParams memory slippageParams = RecurringSwap.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: _array1(ETH_USD_PRICE_FEED),
            shouldInvert: _array1(true)
        });
        return _createSwapConfig({
            startTime: startTime,
            swapInterval: swapInterval,
            swapLength: swapLength,
            amount: amount,
            isExactOut: isExactOut,
            slippageParams: slippageParams
        });
    }

    function _createSwapConfig(
        uint256 startTime,
        uint256 swapInterval,
        uint256 swapLength,
        uint256 amount,
        bool isExactOut,
        RecurringSwap.SlippageParams memory slippageParams
    ) internal view returns (RecurringSwap.SwapConfig memory) {
        RecurringSwap.SwapWindow memory swapWindow =
            RecurringSwap.SwapWindow({startTime: startTime, interval: swapInterval, length: swapLength});
        bytes memory swapPath;
        if (isExactOut) {
            // Exact out swap
            swapPath = abi.encodePacked(WETH, uint24(500), USDC);
        } else {
            // Exact in swap
            swapPath = abi.encodePacked(USDC, uint24(500), WETH);
        }
        RecurringSwap.SwapParams memory swapParams = RecurringSwap.SwapParams({
            uniswapRouter: UNISWAP_ROUTER,
            recipient: address(aliceWallet),
            tokenIn: USDC,
            tokenOut: WETH,
            amount: amount,
            isExactOut: isExactOut,
            path: swapPath
        });
        RecurringSwap.SwapConfig memory swapConfig =
            RecurringSwap.SwapConfig({swapWindow: swapWindow, swapParams: swapParams, slippageParams: slippageParams});
        return swapConfig;
    }
}
