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

// TODO: Limit orders
// TODO: Liquidation protection
contract RecurringPurchaseTest is Test {
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

    function createPurchaseConfig(uint40 purchaseInterval, uint256 amount)
        internal
        view
        returns (RecurringPurchase.PurchaseConfig memory)
    {
        // Note: We default to exact out here, but it doesn't really matter for the purpose of our tests
        return createPurchaseConfig(purchaseInterval, amount, 30_000e6, 0);
    }

    function createPurchaseConfig(
        uint40 purchaseInterval,
        uint256 amount,
        uint256 amountInMaximum,
        uint256 amountOutMinimum
    ) internal view returns (RecurringPurchase.PurchaseConfig memory) {
        bytes memory swapPath;
        if (amountInMaximum > 0) {
            // Exact out swap
            swapPath = abi.encodePacked(WETH, uint24(500), USDC);
        } else {
            // Exact in swap
            swapPath = abi.encodePacked(USDC, uint24(500), WETH);
        }
        RecurringPurchase.SwapParams memory swapParams = RecurringPurchase.SwapParams({
            uniswapRouter: uniswapRouter,
            recipient: address(aliceWallet),
            tokenFrom: USDC,
            amount: amount,
            amountInMaximum: amountInMaximum,
            amountOutMinimum: amountOutMinimum,
            deadline: type(uint256).max,
            path: swapPath
        });
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            RecurringPurchase.PurchaseConfig({interval: purchaseInterval, swapParams: swapParams});
        return purchaseConfig;
    }

    function testRecurringPurchaseExactInSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingUSDC = 100_000e6;
        deal(USDC, address(aliceWallet), startingUSDC);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToSell = 3_000e6;
        uint256 amountOutMinimum = 1 ether;
        // TODO: swap path might be inversed for exact in...
        RecurringPurchase.PurchaseConfig memory purchaseConfig = createPurchaseConfig({
            purchaseInterval: purchaseInterval,
            amount: amountToSell,
            amountOutMinimum: amountOutMinimum,
            amountInMaximum: 0
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

        assertGt(IERC20(WETH).balanceOf(address(aliceWallet)), amountOutMinimum);
        assertEq(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC - amountToSell);
    }

    function testRecurringPurchaseExactOutSwap() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        uint256 startingUSDC = 100_000e6;
        deal(USDC, address(aliceWallet), startingUSDC);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        uint256 amountInMaximum = 30_000e6;
        RecurringPurchase.PurchaseConfig memory purchaseConfig = createPurchaseConfig({
            purchaseInterval: purchaseInterval,
            amount: amountToPurchase,
            amountOutMinimum: 0,
            amountInMaximum: amountInMaximum
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

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), amountToPurchase);
        assertLt(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC);
        assertGt(IERC20(USDC).balanceOf(address(aliceWallet)), startingUSDC - amountInMaximum);
    }

    function testRecurringPurchaseMultiplePurchases() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 amountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            createPurchaseConfig(purchaseInterval, amountToPurchase);
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
            createPurchaseConfig(purchaseInterval, amountToPurchase);
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
                createPurchaseConfig(purchaseInterval, amountToPurchase1);
            op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
                aliceWallet,
                recurringPurchase,
                abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig1),
                ScriptType.ScriptAddress
            );
            op1.expiry = purchaseConfig1.swapParams.deadline;
            RecurringPurchase.PurchaseConfig memory purchaseConfig2 =
                createPurchaseConfig(purchaseInterval, amountToPurchase2);
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
        RecurringPurchase.PurchaseConfig memory invalidPurchaseConfig1 =
            createPurchaseConfig(purchaseInterval, amountToPurchase, 0, 0);
        RecurringPurchase.PurchaseConfig memory invalidPurchaseConfig2 =
            createPurchaseConfig(purchaseInterval, amountToPurchase, 50_000e6, 10e18);
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
            createPurchaseConfig(purchaseInterval, amountToPurchase);
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
            createPurchaseConfig(purchaseInterval, amountToPurchase);
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
            createPurchaseConfig(purchaseInterval, amountToPurchase);
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
}
