// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {Arrays} from "test/builder/lib/Arrays.sol";
import {Accounts, PaymentInfo, QuarkBuilder, QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";

import {Actions} from "src/builder/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {CometWithdrawActions, TransferActions} from "src/DeFiScripts.sol";
import {Paycall} from "src/Paycall.sol";
import {Quotecall} from "src/Quotecall.sol";

contract QuarkBuilderCometWithdrawTest is Test, QuarkBuilderTest {
    function cometWithdraw_(uint256 chainId, address comet, string memory assetSymbol, uint256 amount)
        internal
        pure
        returns (QuarkBuilder.CometWithdrawIntent memory)
    {
        return QuarkBuilder.CometWithdrawIntent({
            amount: amount,
            assetSymbol: assetSymbol,
            blockTimestamp: BLOCK_TIMESTAMP,
            chainId: chainId,
            comet: comet,
            withdrawer: address(0xa11ce)
        });
    }

    // XXX test that you have enough of the asset to withdraw

    function testCometWithdraw() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometWithdraw(
            cometWithdraw_(1, cometUsdc_(1), "LINK", 1e18),
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
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
                                keccak256(type(CometWithdrawActions).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(CometWithdrawActions.withdraw, (cometUsdc_(1), link_(1), 1e18)),
            "calldata is CometWithdrawActions.withdraw(cometUsdc_(1), LINK_1, 1e18);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainId 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "WITHDRAW", "action type is 'WITHDRAW'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.WithdrawActionContext({
                    amount: 1e18,
                    assetSymbol: "LINK",
                    chainId: 1,
                    comet: cometUsdc_(1),
                    price: LINK_PRICE,
                    token: link_(1)
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometWithdrawWithPaycall() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        QuarkBuilder.BuilderResult memory result = builder.cometWithdraw(
            cometWithdraw_(1, cometUsdc_(1), "LINK", 1e18),
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address cometWithdrawActionsAddress = CodeJarHelper.getCodeAddress(type(CometWithdrawActions).creationCode);
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
                cometWithdrawActionsAddress,
                abi.encodeWithSelector(CometWithdrawActions.withdraw.selector, cometUsdc_(1), link_(1), 1e18),
                0.1e6
            ),
            "calldata is Paycall.run(CometWithdrawActions.withdraw(cometUsdc_(1), LINK_1, 1e18), 0.1e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "WITHDRAW", "action type is 'WITHDRAW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.WithdrawActionContext({
                    amount: 1e18,
                    assetSymbol: "LINK",
                    chainId: 1,
                    comet: cometUsdc_(1),
                    price: LINK_PRICE,
                    token: link_(1)
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometWithdrawPayFromWithdraw() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6}); // action costs .5 USDC
        QuarkBuilder.BuilderResult memory result = builder.cometWithdraw(
            cometWithdraw_(1, cometUsdc_(1), "USDC", 1e6), // user will be withdrawing 1 USDC
            chainAccountsList_(0), // and has no additional USDC balance
            paymentUsdc_(maxCosts)
        );

        address cometWithdrawActionsAddress = CodeJarHelper.getCodeAddress(type(CometWithdrawActions).creationCode);
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
                cometWithdrawActionsAddress,
                abi.encodeWithSelector(CometWithdrawActions.withdraw.selector, cometUsdc_(1), usdc_(1), 1e6),
                0.5e6
            ),
            "calldata is Paycall.run(CometWithdrawActions.withdraw(COMET, USDC_1, 1e6), 0.5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "WITHDRAW", "action type is 'WITHDRAW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment max is set to .1e6 in this test case");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.WithdrawActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    comet: cometUsdc_(1),
                    price: USDC_PRICE,
                    token: usdc_(1)
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testWithdrawNotEnoughFundsToBridge() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 1000e6}); // max cost is 1000 USDC
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.1e6});
        vm.expectRevert(abi.encodeWithSelector(Actions.NotEnoughFundsToBridge.selector, "usdc", 9.98e8, 9.971e8));
        builder.cometWithdraw(
            cometWithdraw_(1, cometUsdc_(1), "USDC", 1e6),
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
            paymentUsdc_(maxCosts)
        );
    }

    function testCometWithdrawWithBridge() public {
        QuarkBuilder builder = new QuarkBuilder();

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e6}); // max cost on base is 1 USDC

        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](2);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkStates: quarkStates_(address(0xa11ce), 12),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), 3e6), // 3 USDC on mainnet
            cometPositions: emptyCometPositions_()
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkStates: quarkStates_(address(0xb0b), 2),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), 0), // 0 USDC on base
            cometPositions: emptyCometPositions_()
        });

        QuarkBuilder.BuilderResult memory result = builder.cometWithdraw(
            cometWithdraw_(8453, cometUsdc_(8453), "LINK", 5e18), chainAccountsList, paymentUsdc_(maxCosts)
        );

        address paycallAddress = paycallUsdc_(1);
        address paycallAddressBase = paycallUsdc_(8453);
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        // Check the quark operations
        // first operation
        assertEq(result.quarkOperations.length, 2, "two operations");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            paycallAddress,
            "script address is correct given the code jar address on base"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cctpBridgeActionsAddress,
                abi.encodeWithSelector(
                    CCTPBridgeActions.bridgeUSDC.selector,
                    address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155),
                    1e6,
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                ),
                0.1e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(0xBd3fa81B58Ba92a82136038B25aDec7066af3155, 1e6, 6, 0xa11ce, USDC_1)), 0.1e6);"
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
                CodeJarHelper.getCodeAddress(type(CometWithdrawActions).creationCode),
                abi.encodeCall(CometWithdrawActions.withdraw, (cometUsdc_(8453), link_(8453), 5e18)),
                1e6
            ),
            "calldata is Paycall.run(CometWithdrawActions.withdraw(COMET, LINK_8453, 5e18), 1e6);"
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
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment should have max cost of 0.1e6");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    bridgeType: Actions.BRIDGE_TYPE_CCTP,
                    chainId: 1,
                    destinationChainId: 8453,
                    price: USDC_PRICE,
                    recipient: address(0xa11ce),
                    token: USDC_1
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        // second action
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[1].actionType, "WITHDRAW", "action type is 'WITHDRAW'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 1e6, "payment should have max cost of 1e6");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.WithdrawActionContext({
                    amount: 5e18,
                    assetSymbol: "LINK",
                    chainId: 8453,
                    comet: cometUsdc_(8453),
                    price: LINK_PRICE,
                    token: link_(8453)
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometWithdrawMaxRevertsMaxCostTooHigh() public {
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 100e6}); // max cost is very high

        CometPortfolio[] memory cometPortfolios = new CometPortfolio[](1);
        cometPortfolios[0] = CometPortfolio({
            comet: cometUsdc_(1),
            baseSupplied: 1e6,
            baseBorrowed: 0,
            collateralAssetSymbols: Arrays.stringArray("LINK"),
            collateralAssetBalances: Arrays.uintArray(0)
        });

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](1);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: cometPortfolios
        });

        QuarkBuilder builder = new QuarkBuilder();

        vm.expectRevert(QuarkBuilder.MaxCostTooHigh.selector);

        builder.cometWithdraw(
            cometWithdraw_(1, cometUsdc_(1), "USDC", type(uint256).max),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts) // user will pay for transaction with withdrawn funds, but it is not enough
        );
    }

    function testCometWithdrawMax() public {
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});

        CometPortfolio[] memory cometPortfolios = new CometPortfolio[](1);
        cometPortfolios[0] = CometPortfolio({
            comet: cometUsdc_(1),
            baseSupplied: 1e6,
            baseBorrowed: 0,
            collateralAssetSymbols: Arrays.stringArray("LINK"),
            collateralAssetBalances: Arrays.uintArray(0)
        });

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](1);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: cometPortfolios
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometWithdraw(
            cometWithdraw_(1, cometUsdc_(1), "USDC", type(uint256).max),
            chainAccountsFromChainPortfolios(chainPortfolios), // user has no assets
            paymentUsdc_(maxCosts) // but will pay from withdrawn funds
        );

        address quoteCallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        address cometWithdrawActionsAddress = CodeJarHelper.getCodeAddress(type(CometWithdrawActions).creationCode);

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

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
                cometWithdrawActionsAddress,
                abi.encodeWithSelector(
                    CometWithdrawActions.withdraw.selector, cometUsdc_(1), usdc_(1), type(uint256).max
                ),
                0.1e6
            ),
            "calldata is Quotecall.run(CometWithdrawActions.withdraw(COMET, USDC_1, uint256.max), 0.1e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainId 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "WITHDRAW", "action type is 'WITHDRAW'");
        assertEq(result.actions[0].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to 0.1e6");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.WithdrawActionContext({
                    amount: type(uint256).max, // ?? should this be a different amount?
                    assetSymbol: "USDC",
                    chainId: 1,
                    comet: cometUsdc_(1),
                    price: USDC_PRICE,
                    token: usdc_(1)
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    // XXX reverts if the withdrawn amount is not sufficient to cover the cost of the action
}
