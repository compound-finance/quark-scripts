// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilderTest, Accounts, PaymentInfo, QuarkBuilder} from "test/builder/lib/QuarkBuilderTest.sol";

import {Actions} from "src/builder/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {CometSupplyActions, TransferActions} from "src/DeFiScripts.sol";
import {Paycall} from "src/Paycall.sol";

contract QuarkBuilderCometSupplyTest is Test, QuarkBuilderTest {
    address constant COMET = address(0xc3);

    function cometSupply_(uint256 chainId, uint256 amount)
        internal
        pure
        returns (QuarkBuilder.CometSupplyIntent memory)
    {
        return QuarkBuilder.CometSupplyIntent({
            amount: amount,
            assetSymbol: "USDC",
            blockTimestamp: BLOCK_TIMESTAMP,
            chainId: chainId,
            comet: COMET,
            sender: address(0xa11ce)
        });
    }

    function testInsufficientFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 2e6, 0e6));
        builder.cometSupply(
            cometSupply_(1, 2e6),
            chainAccountsList_(0e6), // but we are holding 0 USDC in total across 1, 8453
            paymentUsd_()
        );
    }

    function testMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        // Max cost is too high, so total available funds is 0
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 1e6, 0e6));
        builder.cometSupply(
            cometSupply_(1, 1e6),
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
            paymentUsdc_(maxCosts_(1, 1_000e6)) // but costs 1,000 USDC
        );
    }

    function testFundsUnavailable() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 2e6, 0));
        builder.cometSupply(
            // there is no bridge to chain 7777, so we cannot get to our funds
            cometSupply_(7777, 2e6), // transfer 2 USDC on chain 7777 to 0xfe11a
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsd_()
        );
    }

    function testSimpleCometSupply() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometSupply(
            cometSupply_(1, 1e6),
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
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
                                keccak256(type(CometSupplyActions).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(CometSupplyActions.supply, (COMET, usdc_(1), 1e6)),
            "calldata is CometSupplyActions.supply(COMET, usdc, 2);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "SUPPLY", "action type is 'SUPPLY'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.SupplyActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    comet: COMET,
                    price: 1e8,
                    token: USDC_1
                })
            ),
            "action context encoded from SupplyActionContext"
        );

        // // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometSupplyWithPaycall() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        QuarkBuilder.BuilderResult memory result = builder.cometSupply(
            cometSupply_(1, 1e6),
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address cometSupplyActionsAddress = CodeJarHelper.getCodeAddress(type(CometSupplyActions).creationCode);
        address paycallAddress = paycallUsdc_(1);

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
                cometSupplyActionsAddress,
                abi.encodeWithSelector(CometSupplyActions.supply.selector, COMET, usdc_(1), 1e6),
                0.1e6
            ),
            "calldata is Paycall.run(CometSupplyActions.supply(COMET, USDC, 1e6), 0.1e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "SUPPLY", "action type is 'SUPPLY'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.SupplyActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    comet: COMET,
                    price: 1e8,
                    token: USDC_1
                })
            ),
            "action context encoded from SupplyActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometSupplyWithBridge() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometSupply(
            cometSupply_(8453, 5e6),
            chainAccountsList_(6e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        // Check the quark operations
        // first operation
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
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(
                CCTPBridgeActions.bridgeUSDC,
                (
                    address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155),
                    2e6,
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

        // second operation
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
                                keccak256(type(CometSupplyActions).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address for transfer is correct given the code jar address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeCall(CometSupplyActions.supply, (COMET, usdc_(8453), 5e6)),
            "calldata is CometSupplyActions.supply(COMET, usdc, 5e6);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        // first action
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
                    amount: 2e6,
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

        // second action
        assertEq(result.actions[1].chainId, 8453, "second action is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[1].actionType, "SUPPLY", "action type is 'SUPPLY'");
        assertEq(result.actions[1].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[1].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[1].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SupplyActionContext({
                    amount: 5e6,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    comet: COMET,
                    price: 1e8,
                    token: USDC_8453
                })
            ),
            "action context encoded from SupplyActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometSupplyWithBridgeAndPaycall() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.1e6});

        // Note: There are 3e6 USDC on each chain, so the Builder should attempt to bridge 2 USDC to chain 8453
        QuarkBuilder.BuilderResult memory result = builder.cometSupply(
            cometSupply_(8453, 5e6),
            chainAccountsList_(6e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address paycallAddress = paycallUsdc_(1);
        address paycallAddressBase = paycallUsdc_(8453);
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);

        assertEq(result.paymentCurrency, "usdc", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 2, "two operations");
        // first operation
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
                    2.1e6,
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                ),
                0.5e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 2.1e6, 6, bytes32(uint256(uint160(0xa11ce))), usdc_(1))), 0.5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // second operation
        assertEq(
            result.quarkOperations[1].scriptAddress,
            paycallAddressBase,
            "script address[1] has been wrapped with paycall address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                CodeJarHelper.getCodeAddress(type(CometSupplyActions).creationCode),
                abi.encodeCall(CometSupplyActions.supply, (COMET, usdc_(8453), 5e6)),
                0.1e6
            ),
            "calldata is Paycall.run(CometSupplyActions.supply(COMET, usdc(8453), 5e6), 0.1e6);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // Check the actions
        assertEq(result.actions.length, 2, "two actions");
        // first action
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment should have max cost of 0.5e6");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    amount: 2.1e6,
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
        // second action
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[1].actionType, "SUPPLY", "action type is 'SUPPLY'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 0.1e6, "payment should have max cost of 0.1e6");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SupplyActionContext({
                    amount: 5e6,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    comet: COMET,
                    price: 1e8,
                    token: USDC_8453
                })
            ),
            "action context encoded from SupplyActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }
}
