// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";

import {ApproveAndSwap} from "src/DeFiScripts.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";

import {Actions} from "src/builder/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";
import {Paycall} from "src/Paycall.sol";
import {Quotecall} from "src/Quotecall.sol";
import {PaycallWrapper} from "src/builder/PaycallWrapper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";

contract QuarkBuilderSwapTest is Test, QuarkBuilderTest {
    uint256 constant BLOCK_TIMESTAMP = 123_456_789;
    address constant MATCHA_ENTRY_POINT = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    bytes constant MATCHA_SWAP_DATA = hex"abcdef";

    function buyWeth_(
        uint256 chainId,
        address sellToken,
        uint256 sellAmount,
        uint256 expectedBuyAmount,
        address sender,
        uint256 blockTimestamp
    ) internal pure returns (QuarkBuilder.MatchaSwapIntent memory) {
        address weth = weth_(chainId);
        return matchaSwap_(
            chainId,
            MATCHA_ENTRY_POINT,
            MATCHA_SWAP_DATA,
            sellToken,
            sellAmount,
            weth,
            expectedBuyAmount,
            sender,
            blockTimestamp
        );
    }

    function matchaSwap_(
        uint256 chainId,
        address entryPoint,
        bytes memory swapData,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 expectedBuyAmount,
        address sender,
        uint256 blockTimestamp
    ) internal pure returns (QuarkBuilder.MatchaSwapIntent memory) {
        return QuarkBuilder.MatchaSwapIntent({
            chainId: chainId,
            entryPoint: entryPoint,
            swapData: swapData,
            sellToken: sellToken,
            sellAmount: sellAmount,
            buyToken: buyToken,
            expectedBuyAmount: expectedBuyAmount,
            sender: sender,
            blockTimestamp: blockTimestamp
        });
    }

    function testInsufficientFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 3000e6, 0e6));
        builder.swap(
            buyWeth_(1, usdc_(1), 3000e6, 1e18, address(0xfe11a), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 1 to 1 WETH
            chainAccountsList_(0e6), // but we are holding 0 USDC in total across 1, 8453
            paymentUsd_()
        );
    }

    // TODO: This no longer tests for the MaxCostTooHigh, since it may be unreachable now. Verify that this is the case.
    function testMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        // Max cost is too high, so total available funds is 0
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 30e6, 0e6));
        builder.swap(
            buyWeth_(1, usdc_(1), 30e6, 0.01e18, address(0xfe11a), BLOCK_TIMESTAMP), // swap 30 USDC on chain 1 to 0.01 WETH
            chainAccountsList_(60e6), // holding 60 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts_(1, 1_000e6)) // but costs 1,000 USDC
        );
    }

    function testFundsOnUnbridgeableChains() public {
        QuarkBuilder builder = new QuarkBuilder();
        // FundsUnavailable("USDC", 2e6, 0e6): Requested 2e6, Available 0e6
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 30e6, 0e6));
        builder.swap(
            // there is no bridge to chain 7777, so we cannot get to our funds
            buyWeth_(7777, usdc_(7777), 30e6, 0.01e18, address(0xfe11a), BLOCK_TIMESTAMP), // swap 30 USDC on chain 1 to 0.01 WETH
            chainAccountsList_(60e6), // holding 60 USDC in total across chains 1, 8453
            paymentUsd_()
        );
    }

    function testFundsUnavailableErrorGivesSuggestionForAvailableFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        // The 32e6 is the suggested amount (total available funds) to swap
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 30e6, 27e6));
        builder.swap(
            buyWeth_(1, usdc_(1), 30e6, 0.01e18, address(0xfe11a), BLOCK_TIMESTAMP), // swap 30 USDC on chain 1 to 0.01 WETH
            chainAccountsList_(60e6), // holding 60 USDC in total across 1, 8453
            paymentUsdc_(maxCosts_(1, 3e6)) // but costs 3 USDC
        );
    }

    // TODO: Test selling WETH as well
    function testLocalSwapSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.swap(
            buyWeth_(1, usdc_(1), 3000e6, 1e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 1 to 1 WETH
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
                                keccak256(type(ApproveAndSwap).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(ApproveAndSwap.run, (MATCHA_ENTRY_POINT, USDC_1, 3000e6, WETH_1, 1e18, MATCHA_SWAP_DATA)),
            "calldata is ApproveAndSwap.run(MATCHA_ENTRY_POINT, USDC_1, 3500e6, WETH_1, 1e18, MATCHA_SWAP_DATA);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce does the swap");
        assertEq(result.actions[0].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 1,
                    inputToken: USDC_1,
                    inputTokenPrice: 1e8,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_1,
                    outputTokenPrice: 3000e8,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18
                })
            ),
            "action context encoded from SwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testLocalSwapWithPaycallSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 5e6});
        QuarkBuilder.BuilderResult memory result = builder.swap(
            buyWeth_(1, usdc_(1), 3000e6, 1e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 1 to 1 WETH
            chainAccountsList_(6010e6), // holding 6010 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address approveAndSwapAddress = CodeJarHelper.getCodeAddress(type(ApproveAndSwap).creationCode);
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
                approveAndSwapAddress,
                abi.encodeWithSelector(
                    ApproveAndSwap.run.selector, MATCHA_ENTRY_POINT, USDC_1, 3000e6, WETH_1, 1e18, MATCHA_SWAP_DATA
                ),
                5e6
            ),
            "calldata is Paycall.run(ApproveAndSwap.run(MATCHA_ENTRY_POINT, USDC_1, 3500e6, WETH_1, 1e18, MATCHA_SWAP_DATA), 5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce does the swap");
        assertEq(result.actions[0].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment max is set to 5e6 in this test case");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 1,
                    inputToken: USDC_1,
                    inputTokenPrice: 1e8,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_1,
                    outputTokenPrice: 3000e8,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18
                })
            ),
            "action context encoded from SwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBridgeSwapSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.swap(
            buyWeth_(8453, usdc_(8453), 3000e6, 1e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 8453 to 1 WETH
            chainAccountsList_(4000e6), // holding 4000 USDC in total across chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 2, "two operations");
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
                                keccak256(type(CCTPBridgeActions).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address for bridge action is correct given the code jar address"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(
                CCTPBridgeActions.bridgeUSDC,
                (
                    address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155),
                    1000e6,
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                )
            ),
            "calldata is CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 2e6, 6, bytes32(uint256(uint160(0xa11ce))), usdc_(1)));"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(
            result.quarkOperations[1].scriptAddress,
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
                                keccak256(type(ApproveAndSwap).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address for transfer is correct given the code jar address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeCall(
                ApproveAndSwap.run, (MATCHA_ENTRY_POINT, USDC_8453, 3000e6, WETH_8453, 1e18, MATCHA_SWAP_DATA)
            ),
            "calldata is ApproveAndSwap.run(MATCHA_ENTRY_POINT, USDC_8453, 3500e6, WETH_8453, 1e18, MATCHA_SWAP_DATA);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );

        // Check the actions
        assertEq(result.actions.length, 2, "two actions");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    amount: 1000e6,
                    price: 1e8,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    chainId: 1,
                    recipient: address(0xa11ce),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[1].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[1].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[1].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[1].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 8453,
                    inputToken: USDC_8453,
                    inputTokenPrice: 1e8,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_8453,
                    outputTokenPrice: 3000e8,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18
                })
            ),
            "action context encoded from SwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBridgeSwapWithPaycallSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 5e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e6});
        // Note: There are 2000e6 USDC on each chain, so the Builder should attempt to bridge 1000 + 1 (for payment) USDC to chain 8453
        QuarkBuilder.BuilderResult memory result = builder.swap(
            buyWeth_(8453, usdc_(8453), 3000e6, 1e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 8453 to 1 WETH
            chainAccountsList_(4000e6), // holding 4000 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address approveAndSwapAddress = CodeJarHelper.getCodeAddress(type(ApproveAndSwap).creationCode);
        address paycallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        address paycallAddressBase = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
        );
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 2, "two operations");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            paycallAddress,
            "script address[0] has been wrapped with paycall address"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cctpBridgeActionsAddress,
                abi.encodeWithSelector(
                    CCTPBridgeActions.bridgeUSDC.selector,
                    address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155),
                    1001e6,
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                ),
                5e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 2.1e6, 6, bytes32(uint256(uint160(0xa11ce))), usdc_(1))), 5e5);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(
            result.quarkOperations[1].scriptAddress,
            paycallAddressBase,
            "script address[1] has been wrapped with paycall address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                approveAndSwapAddress,
                abi.encodeWithSelector(
                    ApproveAndSwap.run.selector,
                    MATCHA_ENTRY_POINT,
                    USDC_8453,
                    3000e6,
                    WETH_8453,
                    1e18,
                    MATCHA_SWAP_DATA
                ),
                1e6
            ),
            "calldata is Paycall.run(ApproveAndSwap.run(MATCHA_ENTRY_POINT, USDC_8453, 3500e6, WETH_8453, 1e18, MATCHA_SWAP_DATA), 5e6);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );

        // Check the actions
        assertEq(result.actions.length, 2, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment should have max cost of 5e6");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    amount: 1001e6,
                    price: 1e8,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    chainId: 1,
                    recipient: address(0xa11ce),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[1].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 1e6, "payment should have max cost of 1e6");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 8453,
                    inputToken: USDC_8453,
                    inputTokenPrice: 1e8,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_8453,
                    outputTokenPrice: 3000e8,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18
                })
            ),
            "action context encoded from SwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBridgeSwapBridgesPaymentToken() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 5e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 3500e6});
        // Note: There are 3000e6 USDC on each chain, so the Builder should attempt to bridge 500 USDC to chain 8453 to cover the max cost
        QuarkBuilder.BuilderResult memory result = builder.swap(
            buyWeth_(8453, usdt_(8453), 3000e6, 1e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 3000 USDT on chain 8453 to 1 WETH
            chainAccountsList_(6000e6), // holding 6000 USDC and USDT in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address approveAndSwapAddress = CodeJarHelper.getCodeAddress(type(ApproveAndSwap).creationCode);
        address paycallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        address paycallAddressBase = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
        );
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 2, "two operations");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            paycallAddress,
            "script address[0] has been wrapped with paycall address"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cctpBridgeActionsAddress,
                abi.encodeWithSelector(
                    CCTPBridgeActions.bridgeUSDC.selector,
                    address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155),
                    500e6,
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                ),
                5e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 500e6, 6, bytes32(uint256(uint160(0xa11ce))), usdc_(1))), 5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                approveAndSwapAddress,
                abi.encodeWithSelector(
                    ApproveAndSwap.run.selector,
                    MATCHA_ENTRY_POINT,
                    USDT_8453,
                    3000e6,
                    WETH_8453,
                    1e18,
                    MATCHA_SWAP_DATA
                ),
                3500e6
            ),
            "calldata is Paycall.run(ApproveAndSwap.run(MATCHA_ENTRY_POINT, USDT_8453, 3500e6, WETH_8453, 1e18, MATCHA_SWAP_DATA), 3500e6);"
        );
        assertEq(
            result.quarkOperations[1].scriptAddress,
            paycallAddressBase,
            "script address[1] has been wrapped with paycall address"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );

        // Check the actions
        assertEq(result.actions.length, 2, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment should have max cost of 5e6");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    amount: 500e6,
                    price: 1e8,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    chainId: 1,
                    recipient: address(0xa11ce),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[1].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 3500e6, "payment should have max cost of 3500e6");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 8453,
                    inputToken: USDT_8453,
                    inputTokenPrice: 1e8,
                    inputAssetSymbol: "USDT",
                    inputAmount: 3000e6,
                    outputToken: WETH_8453,
                    outputTokenPrice: 3000e8,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18
                })
            ),
            "action context encoded from SwapActionContext"
        );
        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testIgnoresChainIfMaxCostIsNotSpecified() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e6});

        // Note: There are 2000e6 USDC on each chain, so the Builder should attempt to bridge 1001 USDC to chain 8453.
        // The extra 1 USDC is to cover the payment max cost on chain 8453.
        // However, max cost is not specified for chain 1, so the Builder will ignore the chain and revert because
        // there will be insufficient funds for the transfer.

        // The `FundsAvailable` error tells us that 3000 USDC was asked to be swap, but only 1999 USDC was available.
        // (1999 USDC instead of 2000 USDC because 1 USDC is reserved for the payment max cost)
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 3000e6, 1999e6));
        builder.swap(
            buyWeth_(8453, usdc_(8453), 3000e6, 1e18, address(0xfe11a), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 8453 to 1 WETH
            chainAccountsList_(4000e6), // holding 4000 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );
    }

    function testRevertsIfNotEnoughFundsToBridge() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 3000e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 3001e6});

        // Note: Need to bridge 1 USDC to cover max cost on chain 8453, but there is 0 available to bridge from chain 1 because they
        // are all reserved for the max cost on chain 1.
        vm.expectRevert(abi.encodeWithSelector(Actions.NotEnoughFundsToBridge.selector, "usdc", 1e6, 1e6));
        builder.swap(
            buyWeth_(8453, usdt_(8453), 3000e6, 1e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 3000 USDT on chain 8453 to 1 WETH
            chainAccountsList_(6000e6), // holding 6000 USDT in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );
    }
}
