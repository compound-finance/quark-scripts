// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TransferActions} from "../src/DeFiScripts.sol";
import {CCTPBridgeActions} from "../src/BridgeScripts.sol";

import {Actions} from "../src/builder/Actions.sol";
import {Accounts} from "../src/builder/Accounts.sol";
import {CodeJarHelper} from "../src/builder/CodeJarHelper.sol";
import {QuarkBuilder} from "../src/builder/QuarkBuilder.sol";
import {Paycall} from "../src/Paycall.sol";
import {Quotecall} from "../src/Quotecall.sol";
import {PaycallWrapper} from "../src/builder/PaycallWrapper.sol";
import {PaymentInfo} from "../src/builder/PaymentInfo.sol";

contract QuarkBuilderTest is Test {
    uint256 constant BLOCK_TIMESTAMP = 123_456_789;
    address constant ETH_USD_PRICE_FEED_1 = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant ETH_USD_PRICE_FEED_8453 = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant USDC_1 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_8453 = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    // Random address for mock of USDC in random unsupported L2 chain
    address constant USDC_7777 = 0x8D89c5CaA76592e30e0410B9e68C0f235c62B312;

    function testInsufficientFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.InsufficientFunds.selector, 10e6, 0e6));
        builder.transfer(
            transferUsdc_(1, 10e6, address(0xfe11a), BLOCK_TIMESTAMP), // transfer 10USDC on chain 1 to 0xfe11a
            chainAccountsList_(0e6), // but we are holding 0 USDC in total across 1, 8453
            paymentUsd_()
        );
    }

    function testMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(QuarkBuilder.MaxCostTooHigh.selector);
        builder.transfer(
            transferUsdc_(1, 1e6, address(0xfe11a), BLOCK_TIMESTAMP), // transfer 1USDC on chain 1 to 0xfe11a
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
            paymentUsdc_(maxCosts_(1, 1_000e6)) // but costs 1,000USDC
        );
    }

    function testFundsUnavailable() public {
        QuarkBuilder builder = new QuarkBuilder();
        // FundsUnavailable(2e6, 0e6, 2e6): Requested 2e6, Available 0e6, Still missing 2e6
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, 2e6, 0e6, 2e6));
        builder.transfer(
            // there is no bridge to chain 7777, so we cannot get to our funds
            transferUsdc_(7777, 2e6, address(0xfe11a), BLOCK_TIMESTAMP), // transfer 2USDC on chain 7777 to 0xfe11a
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsd_()
        );
    }

    function testSimpleLocalTransferSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.transfer(
            transferUsdc_(1, 1e6, address(0xceecee), BLOCK_TIMESTAMP), // transfer 1 usdc on chain 1 to 0xceecee
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.version, "1.0.0", "version 1");
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
                                keccak256(type(TransferActions).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(TransferActions.transferERC20Token, (usdc_(1), address(0xceecee), 1e6)),
            "calldata is TransferActions.transferERC20Token(USDC_1, address(0xceecee), 1e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.TransferActionContext({
                    amount: 1e6,
                    price: 1e8,
                    token: USDC_1,
                    chainId: 1,
                    recipient: address(0xceecee)
                })
            ),
            "action context encoded from TransferActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testSimpleLocalTransferWithPaycallSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 1e5});
        QuarkBuilder.BuilderResult memory result = builder.transfer(
            transferUsdc_(1, 1e6, address(0xceecee), BLOCK_TIMESTAMP), // transfer 1 usdc on chain 1 to 0xceecee
            chainAccountsList_(3e6), // holding 3USDC on chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address transferActionsAddress = CodeJarHelper.getCodeAddress(type(TransferActions).creationCode);
        address paycallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );

        assertEq(result.version, "1.0.0", "version 1");
        assertEq(result.paymentCurrency, "usdc", "usd currency");

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
                transferActionsAddress,
                abi.encodeWithSelector(TransferActions.transferERC20Token.selector, usdc_(1), address(0xceecee), 1e6),
                1e5
            ),
            "calldata is Paycall.run(TransferActions.transferERC20Token(USDC_1, address(0xceecee), 1e6), 20e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 1e5, "payment max is set to 1e5 in this test case");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.TransferActionContext({
                    amount: 1e6,
                    price: 1e8,
                    token: USDC_1,
                    chainId: 1,
                    recipient: address(0xceecee)
                })
            ),
            "action context encoded from TransferActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testSimpleBridgeTransferSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        // Note: There are 3e6 USDC on each chain, so the Builder should attempt to bridge 2 USDC to chain 8453
        QuarkBuilder.BuilderResult memory result = builder.transfer(
            transferUsdc_(8453, 5e6, address(0xceecee), BLOCK_TIMESTAMP), // transfer 5 USDC on chain 8453 to 0xceecee
            chainAccountsList_(6e6), // holding 6 USDC in total across chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.version, "1.0.0", "version 1");
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
                                keccak256(type(TransferActions).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address for transfer is correct given the code jar address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeCall(TransferActions.transferERC20Token, (usdc_(8453), address(0xceecee), 5e6)),
            "calldata is TransferActions.transferERC20Token(USDC_8453, address(0xceecee), 5e6);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // Check the actions
        assertEq(result.actions.length, 2, "one action");
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
        assertEq(result.actions[1].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.actions[1].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[1].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[1].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.TransferActionContext({
                    amount: 5e6,
                    price: 1e8,
                    token: USDC_8453,
                    chainId: 8453,
                    recipient: address(0xceecee)
                })
            ),
            "action context encoded from TransferActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testSimpleBridgeTransferWithPaycallSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 5e5});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e5});

        // Note: There are 3e6 USDC on each chain, so the Builder should attempt to bridge 2 USDC to chain 8453
        QuarkBuilder.BuilderResult memory result = builder.transfer(
            transferUsdc_(8453, 5e6, address(0xceecee), BLOCK_TIMESTAMP), // transfer 5 USDC on chain 8453 to 0xceecee
            chainAccountsList_(6e6), // holding 6 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );
        address paycallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        address paycallAddressBase = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
        );
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);
        assertEq(result.version, "1.0.0", "version 1");
        assertEq(result.paymentCurrency, "usdc", "usd currency");

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
                    2.1e6,
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                ),
                0.5e6
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
                CodeJarHelper.getCodeAddress(type(TransferActions).creationCode),
                abi.encodeWithSelector(TransferActions.transferERC20Token.selector, usdc_(8453), address(0xceecee), 5e6),
                0.1e6
            ),
            "calldata is Paycall.run(TransferActions.transferERC20Token(USDC_8453, address(0xceecee), 5e6), 1e5);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // Check the actions
        assertEq(result.actions.length, 2, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment should have max cost of 5e5");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    amount: 2.1e6,
                    price: 1e8,
                    token: USDC_1,
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
        assertEq(result.actions[1].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 0.1e6, "payment should have max cost of 1e5");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.TransferActionContext({
                    amount: 5e6,
                    price: 1e8,
                    token: USDC_8453,
                    chainId: 8453,
                    recipient: address(0xceecee)
                })
            ),
            "action context encoded from TransferActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testSimpleLocalTransferMax() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 1e5});
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](1);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkStates: quarkStates_(address(0xa11ce), 12),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), uint256(10e6))
        });

        QuarkBuilder.BuilderResult memory result = builder.transfer(
            transferUsdc_(1, type(uint256).max, address(0xceecee), BLOCK_TIMESTAMP), // transfer max
            chainAccountsList,
            paymentUsdc_(maxCosts)
        );

        address transferActionsAddress = CodeJarHelper.getCodeAddress(type(TransferActions).creationCode);
        address quoteCallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );

        assertEq(result.version, "1.0.0", "version 1");
        assertEq(result.paymentCurrency, "usdc", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            quoteCallAddress,
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                transferActionsAddress,
                // Transfermax should be able to adjust to the right maxz amount to transfer all funds: 10e6 (holding) - 1e5 (max cost) = 9.9e6
                abi.encodeWithSelector(TransferActions.transferERC20Token.selector, usdc_(1), address(0xceecee), 9.9e6),
                1e5
            ),
            "calldata is Quotecall.run(TransferActions.transferERC20Token(USDC_1, address(0xceecee), 9.9e6), 1e5);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.actions[0].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 1e5, "payment max is set to 1e5 in this test case");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.TransferActionContext({
                    amount: 9.9e6,
                    price: 1e8,
                    token: USDC_1,
                    chainId: 1,
                    recipient: address(0xceecee)
                })
            ),
            "action context encoded from TransferActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testSimpleBridgeTransferMax() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.1e6});
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](2);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkStates: quarkStates_(address(0xa11ce), 12),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), 8e6)
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkStates: quarkStates_(address(0xb0b), 2),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), 4e6)
        });

        QuarkBuilder.BuilderResult memory result = builder.transfer(
            transferUsdc_(8453, type(uint256).max, address(0xceecee), BLOCK_TIMESTAMP), // transfer max USDC on chain 8453 to 0xceecee
            chainAccountsList, // holding 8 USDC on chains 1, and 4 USDC on 8453
            paymentUsdc_(maxCosts)
        );
        address quotecallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        address quotecallAddressBase = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
        );
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);
        assertEq(result.version, "1.0.0", "version 1");
        assertEq(result.paymentCurrency, "usdc", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 2, "two operations");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            quotecallAddress,
            "script address[0] has been wrapped with quotecall address"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                cctpBridgeActionsAddress,
                abi.encodeWithSelector(
                    CCTPBridgeActions.bridgeUSDC.selector,
                    address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155),
                    7.5e6, // 8e6 (holdings on mainnet) - 0.5e6 (max cost on mainnet)
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                ),
                0.5e6
            ),
            "calldata is Quote.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 7.5e6, 6, bytes32(uint256(uint160(0xa11ce))), usdc_(1))), 0.5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(
            result.quarkOperations[1].scriptAddress,
            quotecallAddressBase,
            "script address[1] has been wrapped with quotecall address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                CodeJarHelper.getCodeAddress(type(TransferActions).creationCode),
                // Transfermax should be able to adjust to the right max amount to transfer all funds: 4e6 (holdings on base) - 0.1e6 (max cost on base) + 7.5e6 (brdiged from mainnet)= 3.9e6 + 7.5e6 = 11.4e6
                abi.encodeWithSelector(
                    TransferActions.transferERC20Token.selector, usdc_(8453), address(0xceecee), 11.4e6
                ),
                0.1e6
            ),
            "calldata is Quotecall.run(TransferActions.transferERC20Token(USDC_8453, address(0xceecee), 11.4e6), 0.1e6);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // Check the actions
        assertEq(result.actions.length, 2, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment should have max cost of 5e5");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    amount: 7.5e6,
                    price: 1e8,
                    token: USDC_1,
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
        assertEq(result.actions[1].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.actions[1].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 0.1e6, "payment should have max cost of 1e5");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.TransferActionContext({
                    amount: 11.4e6,
                    price: 1e8,
                    token: USDC_8453,
                    chainId: 8453,
                    recipient: address(0xceecee)
                })
            ),
            "action context encoded from TransferActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBridgeTransferMaxFundUnavailableError() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](3);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.1e6});
        maxCosts[2] = PaymentInfo.PaymentMaxCost({chainId: 7777, amount: 0.1e6}); // Random L2 with no bridge support
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](3);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkStates: quarkStates_(address(0xa11ce), 12),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), 8e6)
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkStates: quarkStates_(address(0xb0b), 2),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), 4e6)
        });
        chainAccountsList[2] = Accounts.ChainAccounts({
            chainId: 7777,
            quarkStates: quarkStates_(address(0xfe11a), 2),
            assetPositionsList: assetPositionsList_(7777, address(0xfe11a), 5e6)
        });

        // User has total holding of 17 USDC, but only 12 USDC is available for transfer/bridge to 8453, and missing 5 USDC stuck in random L2 so will revert with FundsUnavailable error
        // Actual number re-adjusted with max cost gas fee so that the:
        // Request amount = 17 USDC - 0.5 USDC (max cost on main) - 0.1 USDC (max cost on Base) - 0.1 USDC (max cost on RandomL2) = 16.3 USDC
        // Actual amount = 8 USDC (available on main) + 4 USDC (available on Base) - 0.5 USDC - 0.1 UDC = 11.4 USDC
        // Missing amount = 5 USDC - 0.1 USDC = 4.9 USDC
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, 16.3e6, 11.4e6, 4.9e6));
        builder.transfer(
            transferUsdc_(8453, type(uint256).max, address(0xceecee), BLOCK_TIMESTAMP), // transfer max USDC on chain 8453 to 0xceecee
            chainAccountsList, // holding 8 USDC on chains 1, 4 USDC on 8453, 5 USDC on 7777
            paymentUsdc_(maxCosts)
        );
    }

    function testIgnoresChainIfMaxCostIsNotSpecified() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e5});

        // Note: There are 3e6 USDC on each chain, so the Builder should attempt to bridge 2 USDC to chain 8453.
        // However, max cost is not specified for chain 1, so the Builder will ignore the chain and revert because
        // there will be insufficient funds for the transfer.
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.InsufficientFunds.selector, 5e6, 3e6));
        builder.transfer(
            transferUsdc_(8453, 5e6, address(0xceecee), BLOCK_TIMESTAMP), // transfer 5 USDC on chain 8453 to 0xceecee
            chainAccountsList_(6e6), // holding 6 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );
    }

    /**
     *
     * Fixture Functions
     *
     * @dev to avoid variable shadowing warnings and to provide a visual signifier when
     * a function call is used to mock some data, we suffix all of our fixture-generating
     * functions with a single underscore, like so: transferIntent_(...).
     */
    function transferUsdc_(uint256 chainId, uint256 amount, address recipient, uint256 blockTimestamp)
        internal
        pure
        returns (QuarkBuilder.TransferIntent memory)
    {
        return QuarkBuilder.TransferIntent({
            chainId: chainId,
            sender: address(0xa11ce),
            recipient: recipient,
            amount: amount,
            assetSymbol: "USDC",
            blockTimestamp: blockTimestamp
        });
    }

    function paymentUsdc_() internal pure returns (PaymentInfo.Payment memory) {
        return paymentUsdc_(new PaymentInfo.PaymentMaxCost[](0));
    }

    function paymentUsdc_(PaymentInfo.PaymentMaxCost[] memory maxCosts)
        internal
        pure
        returns (PaymentInfo.Payment memory)
    {
        return PaymentInfo.Payment({isToken: true, currency: "usdc", maxCosts: maxCosts});
    }

    function paymentUsd_() internal pure returns (PaymentInfo.Payment memory) {
        return paymentUsd_(new PaymentInfo.PaymentMaxCost[](0));
    }

    function paymentUsd_(PaymentInfo.PaymentMaxCost[] memory maxCosts)
        internal
        pure
        returns (PaymentInfo.Payment memory)
    {
        return PaymentInfo.Payment({isToken: false, currency: "usd", maxCosts: maxCosts});
    }

    function chainAccountsList_(uint256 amount) internal pure returns (Accounts.ChainAccounts[] memory) {
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](2);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkStates: quarkStates_(address(0xa11ce), 12),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), uint256(amount / 2))
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkStates: quarkStates_(address(0xb0b), 2),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), uint256(amount / 2))
        });
        return chainAccountsList;
    }

    function quarkStates_() internal pure returns (Accounts.QuarkState[] memory) {
        Accounts.QuarkState[] memory quarkStates = new Accounts.QuarkState[](1);
        quarkStates[0] = quarkState_();
        return quarkStates;
    }

    function maxCosts_(uint256 chainId, uint256 amount) internal pure returns (PaymentInfo.PaymentMaxCost[] memory) {
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: chainId, amount: amount});
        return maxCosts;
    }

    function assetPositionsList_(uint256 chainId, address account, uint256 balance)
        internal
        pure
        returns (Accounts.AssetPositions[] memory)
    {
        Accounts.AssetPositions[] memory assetPositionsList = new Accounts.AssetPositions[](1);
        assetPositionsList[0] = Accounts.AssetPositions({
            asset: usdc_(chainId),
            symbol: "USDC",
            decimals: 6,
            usdPrice: 1_0000_0000,
            accountBalances: accountBalances_(account, balance)
        });
        return assetPositionsList;
    }

    function accountBalances_(address account, uint256 balance)
        internal
        pure
        returns (Accounts.AccountBalance[] memory)
    {
        Accounts.AccountBalance[] memory accountBalances = new Accounts.AccountBalance[](1);
        accountBalances[0] = Accounts.AccountBalance({account: account, balance: balance});
        return accountBalances;
    }

    function usdc_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return USDC_1;
        if (chainId == 8453) return USDC_8453;
        if (chainId == 7777) return USDC_7777; // Mock with random L2's usdc
        revert("no mock usdc for that chain id bye");
    }

    function quarkStates_(address account, uint96 nextNonce) internal pure returns (Accounts.QuarkState[] memory) {
        Accounts.QuarkState[] memory quarkStates = new Accounts.QuarkState[](1);
        quarkStates[0] = quarkState_(account, nextNonce);
        return quarkStates;
    }

    function quarkState_() internal pure returns (Accounts.QuarkState memory) {
        return quarkState_(address(0xa11ce), 3);
    }

    function quarkState_(address account, uint96 nextNonce) internal pure returns (Accounts.QuarkState memory) {
        return Accounts.QuarkState({account: account, quarkNextNonce: nextNonce});
    }
}
