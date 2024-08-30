// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";

import {RecurringSwap} from "src/RecurringSwap.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";

import {Actions} from "src/builder/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";
import {Paycall} from "src/Paycall.sol";
import {Quotecall} from "src/Quotecall.sol";
import {Multicall} from "src/Multicall.sol";
import {WrapperActions} from "src/WrapperScripts.sol";
import {PaycallWrapper} from "src/builder/PaycallWrapper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {PriceFeeds} from "src/builder/PriceFeeds.sol";
import {UniswapRouter} from "src/builder/UniswapRouter.sol";

contract QuarkBuilderRecurringSwapTest is Test, QuarkBuilderTest {
    function buyWeth_(
        uint256 chainId,
        address sellToken,
        uint256 sellAmount,
        uint256 buyAmount,
        bool isExactOut,
        uint256 interval,
        address sender,
        uint256 blockTimestamp
    ) internal pure returns (QuarkBuilder.RecurringSwapIntent memory) {
        address weth = weth_(chainId);
        return recurringSwap_({
            chainId: chainId,
            sellToken: sellToken,
            sellAmount: sellAmount,
            buyToken: weth,
            buyAmount: buyAmount,
            isExactOut: isExactOut,
            path: abi.encodePacked(address(0), uint24(500), address(1)),
            interval: interval,
            sender: sender,
            blockTimestamp: blockTimestamp
        });
    }

    function recurringSwap_(
        uint256 chainId,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount,
        bool isExactOut,
        bytes memory path,
        uint256 interval,
        address sender,
        uint256 blockTimestamp
    ) internal pure returns (QuarkBuilder.RecurringSwapIntent memory) {
        return QuarkBuilder.RecurringSwapIntent({
            chainId: chainId,
            sellToken: sellToken,
            sellAmount: sellAmount,
            buyToken: buyToken,
            buyAmount: buyAmount,
            isExactOut: isExactOut,
            path: path,
            interval: interval,
            sender: sender,
            blockTimestamp: blockTimestamp
        });
    }

    function constructSwapConfig_(QuarkBuilder.RecurringSwapIntent memory swap)
        internal
        pure
        returns (RecurringSwap.SwapConfig memory)
    {
        RecurringSwap.SwapParams memory swapParams = RecurringSwap.SwapParams({
            uniswapRouter: UniswapRouter.knownRouter(swap.chainId),
            recipient: swap.sender,
            tokenIn: swap.sellToken,
            tokenOut: swap.buyToken,
            amount: swap.isExactOut ? swap.buyAmount : swap.sellAmount,
            isExactOut: swap.isExactOut,
            deadline: type(uint256).max,
            path: swap.path
        });
        (address[] memory priceFeeds, bool[] memory shouldInvert) =
            PriceFeeds.findPriceFeedPath("USD", "ETH", swap.chainId);
        RecurringSwap.SlippageParams memory slippageParams = RecurringSwap.SlippageParams({
            maxSlippage: 1e17, // 1%
            priceFeeds: priceFeeds,
            shouldInvert: shouldInvert
        });
        return RecurringSwap.SwapConfig({
            startTime: swap.blockTimestamp - Actions.AVERAGE_BLOCK_TIME,
            interval: swap.interval,
            swapParams: swapParams,
            slippageParams: slippageParams
        });
    }

    function testInsufficientFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 3000e6, 0e6));
        builder.recurringSwap(
            buyWeth_({
                chainId: 1,
                sellToken: usdc_(1),
                sellAmount: 3000e6,
                buyAmount: 1e18,
                isExactOut: true,
                interval: 86_400,
                sender: address(0xfe11a),
                blockTimestamp: BLOCK_TIMESTAMP
            }), // swap 3000 USDC on chain 1 to 1 WETH
            chainAccountsList_(0e6), // but we are holding 0 USDC in total across 1, 8453
            paymentUsd_()
        );
    }

    function testMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        // Max cost is too high, so total available funds is 0
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 1_030e6, 0e6));
        builder.recurringSwap(
            buyWeth_({
                chainId: 1,
                sellToken: usdc_(1),
                sellAmount: 30e6,
                buyAmount: 0.01e18,
                isExactOut: true,
                interval: 86_400,
                sender: address(0xfe11a),
                blockTimestamp: BLOCK_TIMESTAMP
            }), // swap 30 USDC on chain 1 to 0.01 WETH
            chainAccountsList_(60e6), // holding 60 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts_(1, 1_000e6)) // but costs 1,000 USDC
        );
    }

    function testNotEnoughFundsOnTargetChain() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 80e6, 30e6));
        builder.recurringSwap(
            buyWeth_({
                chainId: 1,
                sellToken: usdc_(1),
                sellAmount: 80e6,
                buyAmount: 1e18,
                isExactOut: true,
                interval: 86_400,
                sender: address(0xfe11a),
                blockTimestamp: BLOCK_TIMESTAMP
            }), // swap 80 USDC on chain 1 to 1 WETH
            chainAccountsList_(60e6), // holding 60 USDC in total across chains 1, 8453
            paymentUsd_()
        );
    }

    function testFundsUnavailableErrorGivesSuggestionForAvailableFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        // The 27e6 is the suggested amount (total available funds) to swap
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 33e6, 27e6));
        builder.recurringSwap(
            buyWeth_({
                chainId: 1,
                sellToken: usdc_(1),
                sellAmount: 30e6,
                buyAmount: 0.01e18,
                isExactOut: true,
                interval: 86_400,
                sender: address(0xfe11a),
                blockTimestamp: BLOCK_TIMESTAMP
            }), // swap 30 USDC on chain 1 to 0.01 WETH
            chainAccountsList_(60e6), // holding 60 USDC in total across 1, 8453
            paymentUsdc_(maxCosts_(1, 3e6)) // but costs 3 USDC
        );
    }

    function testRecurringExactInSwapSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.RecurringSwapIntent memory buyWethIntent = buyWeth_({
            chainId: 1,
            sellToken: usdc_(1),
            sellAmount: 3000e6,
            buyAmount: 1e18,
            isExactOut: false,
            interval: 86_400,
            sender: address(0xfe11a),
            blockTimestamp: BLOCK_TIMESTAMP
        });
        QuarkBuilder.BuilderResult memory result = builder.recurringSwap(
            buyWethIntent, // swap 3000 USDC on chain 1 to 1 WETH
            chainAccountsList_(6000e6), // holding 6000 USDC in total across chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                /* codeJar address */
                                address(CodeJarHelper.CODE_JAR_ADDRESS),
                                uint256(0),
                                /* script bytecode */
                                keccak256(type(RecurringSwap).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(RecurringSwap.swap, (constructSwapConfig_(buyWethIntent))),
            "calldata is RecurringSwap.swap(SwapConfig(...));"
        );
        assertEq(result.quarkOperations[0].expiry, type(uint256).max, "expiry is type(uint256).max");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xfe11a), "0xfe11a does the swap");
        assertEq(result.actions[0].actionType, "RECURRING_SWAP", "action type is 'RECURRING_SWAP'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.RecurringSwapActionContext({
                    chainId: 1,
                    inputToken: USDC_1,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_1,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18,
                    isExactOut: false,
                    interval: 86_400
                })
            ),
            "action context encoded from RecurringSwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testRecurringExactOutSwapSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.RecurringSwapIntent memory buyWethIntent = buyWeth_({
            chainId: 1,
            sellToken: usdc_(1),
            sellAmount: 3000e6,
            buyAmount: 1e18,
            isExactOut: true,
            interval: 86_400,
            sender: address(0xfe11a),
            blockTimestamp: BLOCK_TIMESTAMP
        });
        QuarkBuilder.BuilderResult memory result = builder.recurringSwap(
            buyWethIntent, // swap 3000 USDC on chain 1 to 1 WETH
            chainAccountsList_(6000e6), // holding 6000 USDC in total across chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                /* codeJar address */
                                address(CodeJarHelper.CODE_JAR_ADDRESS),
                                uint256(0),
                                /* script bytecode */
                                keccak256(type(RecurringSwap).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(RecurringSwap.swap, (constructSwapConfig_(buyWethIntent))),
            "calldata is RecurringSwap.swap(SwapConfig(...));"
        );
        assertEq(result.quarkOperations[0].expiry, type(uint256).max, "expiry is type(uint256).max");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xfe11a), "0xfe11a does the swap");
        assertEq(result.actions[0].actionType, "RECURRING_SWAP", "action type is 'RECURRING_SWAP'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.RecurringSwapActionContext({
                    chainId: 1,
                    inputToken: USDC_1,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_1,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18,
                    isExactOut: true,
                    interval: 86_400
                })
            ),
            "action context encoded from RecurringSwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testRecurringSwapWithPaycallSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.RecurringSwapIntent memory buyWethIntent = buyWeth_({
            chainId: 1,
            sellToken: usdc_(1),
            sellAmount: 3000e6,
            buyAmount: 1e18,
            isExactOut: false,
            interval: 86_400,
            sender: address(0xfe11a),
            blockTimestamp: BLOCK_TIMESTAMP
        });
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 5e6});
        QuarkBuilder.BuilderResult memory result = builder.recurringSwap(
            buyWethIntent, // swap 3000 USDC on chain 1 to 1 WETH
            chainAccountsList_(6010e6), // holding 6010 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address recurringSwapAddress = CodeJarHelper.getCodeAddress(type(RecurringSwap).creationCode);
        address paycallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            paycallAddress,
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                recurringSwapAddress,
                abi.encodeWithSelector(RecurringSwap.swap.selector, constructSwapConfig_(buyWethIntent)),
                5e6
            ),
            "calldata is Paycall.run(RecurringSwap.swap(SwapConfig(...)), 5e6);"
        );
        assertEq(result.quarkOperations[0].expiry, type(uint256).max, "expiry is type(uint256).max");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xfe11a), "0xfe11a does the swap");
        assertEq(result.actions[0].actionType, "RECURRING_SWAP", "action type is 'RECURRING_SWAP'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment max is set to 5e6 in this test case");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.RecurringSwapActionContext({
                    chainId: 1,
                    inputToken: USDC_1,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_1,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18,
                    isExactOut: false,
                    interval: 86_400
                })
            ),
            "action context encoded from SwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    // TODO: Test wrapping/unwrapping when new Quark is out
}
