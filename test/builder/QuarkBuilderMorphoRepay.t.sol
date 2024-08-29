// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Arrays} from "test/builder/lib/Arrays.sol";
import {QuarkBuilderTest, Accounts, PaymentInfo} from "test/builder/lib/QuarkBuilderTest.sol";
import {Actions} from "src/builder/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {MorphoBlueActions} from "src/DeFiScripts.sol";
import {Paycall} from "src/Paycall.sol";
import {Strings} from "src/builder/Strings.sol";
import {Multicall} from "src/Multicall.sol";
import {WrapperActions} from "src/WrapperScripts.sol";
import {MorphoInfo} from "src/builder/MorphoInfo.sol";
import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";
import {TokenWrapper} from "src/builder/TokenWrapper.sol";

contract QuarkBuilderMorphoRepayTest is Test, QuarkBuilderTest {
    function repayIntent_(
        uint256 chainId,
        string memory assetSymbol,
        uint256 amount,
        string memory collateralAssetSymbol,
        uint256 collateralAmount
    ) internal pure returns (QuarkBuilder.MorphoRepayIntent memory) {
        return QuarkBuilder.MorphoRepayIntent({
            amount: amount,
            assetSymbol: assetSymbol,
            blockTimestamp: BLOCK_TIMESTAMP,
            repayer: address(0xa11ce),
            chainId: chainId,
            collateralAmount: collateralAmount,
            collateralAssetSymbol: collateralAssetSymbol
        });
    }

    function testMorphoRepayFundsUnavailable() public {
        QuarkBuilder builder = new QuarkBuilder();

        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "USDC", 1e6, 0));

        builder.morphoRepay(
            repayIntent_(1, "USDC", 1e6, "WBTC", 1e8),
            chainAccountsList_(0e6), // but user has 0 USDC
            paymentUsd_()
        );
    }

    function testMorphoRepayMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.5e6}); // action costs .5 USDC

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](1);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 8453,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0.4e6, 0, 0, 1e18), // user does not have enough USDC
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });

        vm.expectRevert(QuarkBuilder.MaxCostTooHigh.selector);

        builder.morphoRepay(
            repayIntent_(8453, "WETH", 1e18, "cbETH", 1e18),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );
    }

    function testMorphoRepay() public {
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(1e6, 0, 0, 0), // has 1 USDC
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoRepay(
            repayIntent_(
                1,
                "USDC",
                1e6, // repaying 1 USDC
                "WBTC",
                1e8 // withdraw WBTC
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
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
                                keccak256(type(MorphoBlueActions).creationCode)
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
                MorphoBlueActions.repayAndWithdrawCollateral,
                (
                    MorphoInfo.getMorphoAddress(),
                    MorphoInfo.getMarketParams(1, "WBTC", "USDC"),
                    1e6,
                    0,
                    1e8,
                    address(0xa11ce),
                    address(0xa11ce)
                )
            ),
            "calldata is MorphoBlueActions.repayAndWithdrawCollateral(MorphoInfo.getMorphoAddress(), MorphoInfo.getMarketParams(1, WBTC, USDC), 1e6, 0, 1e8,  address(0xa11ce),  address(0xa11ce));"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 1);
        assertEq(result.quarkOperations[0].scriptSources[0], type(MorphoBlueActions).creationCode);
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "REPAY", "action type is 'REPAY'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e8;
        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = WBTC_PRICE;
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = wbtc_(1);
        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "WBTC";

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.RepayActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralAssetSymbols: collateralAssetSymbols,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    comet: address(0),
                    price: USDC_PRICE,
                    token: usdc_(1),
                    morpho: MorphoInfo.getMorphoAddress(),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(1, "WBTC", "USDC"))
                })
            ),
            "action context encoded from RepayActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometRepayWithAutoWrapper() public {
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: Arrays.stringArray("USDC", "ETH", "cbETH", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xa11ce),
            nextNonce: 2,
            assetSymbols: Arrays.stringArray("USDC", "ETH", "cbETH", "WETH"),
            assetBalances: Arrays.uintArray(0, 1e18, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoRepay(
            repayIntent_(
                8453,
                "WETH",
                1e18, // repaying 1 WETH
                "cbETH",
                0e18
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        address multicallAddress = CodeJarHelper.getCodeAddress(type(Multicall).creationCode);
        address wrapperActionsAddress = CodeJarHelper.getCodeAddress(type(WrapperActions).creationCode);
        address morphoBlueActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoBlueActions).creationCode);

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one merged operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            multicallAddress,
            "script address is correct given the code jar address on mainnet"
        );
        address[] memory callContracts = new address[](2);
        callContracts[0] = wrapperActionsAddress;
        callContracts[1] = morphoBlueActionsAddress;
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encodeWithSelector(
            WrapperActions.wrapETH.selector, TokenWrapper.getKnownWrapperTokenPair(8453, "WETH").wrapper, 1e18
        );
        callDatas[1] = abi.encodeCall(
            MorphoBlueActions.repayAndWithdrawCollateral,
            (
                MorphoInfo.getMorphoAddress(),
                MorphoInfo.getMarketParams(8453, "cbETH", "WETH"),
                1e18,
                0,
                0e18,
                address(0xa11ce),
                address(0xa11ce)
            )
        );

        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
            "calldata is Multicall.run([wrapperActionsAddress, morphoBlueActionsAddress], [WrapperActions.wrapWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 1e18),  MorphoBlueActions.repayAndWithdrawCollateral(MorphoInfo.getMorphoAddress(), MorphoInfo.getMarketParams(8453, WETH, USDC), 1e18, 0, 0e18, address(0xa11ce), address(0xa11ce))"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 3);
        assertEq(result.quarkOperations[0].scriptSources[0], type(WrapperActions).creationCode);
        assertEq(result.quarkOperations[0].scriptSources[1], type(MorphoBlueActions).creationCode);
        assertEq(result.quarkOperations[0].scriptSources[2], type(Multicall).creationCode);
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "REPAY", "action type is 'REPAY'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0e18;
        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = CBETH_PRICE;
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = cbEth_(8453);
        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "cbETH";

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.RepayActionContext({
                    amount: 1e18,
                    assetSymbol: "WETH",
                    chainId: 8453,
                    collateralAmounts: collateralAmounts,
                    collateralAssetSymbols: collateralAssetSymbols,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    comet: address(0),
                    price: WETH_PRICE,
                    token: weth_(8453),
                    morpho: MorphoInfo.getMorphoAddress(),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(8453, "cbETH", "WETH"))
                })
            ),
            "action context encoded from RepayActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometRepayWithPaycall() public {
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(2e6, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoRepay(
            repayIntent_(
                1,
                "USDC",
                1e6, // repaying 1 USDC
                "WBTC",
                0e8
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts) // and paying with USDC
        );

        address morphoBlueActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoBlueActions).creationCode);
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
                morphoBlueActionsAddress,
                abi.encodeCall(
                    MorphoBlueActions.repayAndWithdrawCollateral,
                    (
                        MorphoInfo.getMorphoAddress(),
                        MorphoInfo.getMarketParams(1, "WBTC", "USDC"),
                        1e6,
                        0,
                        0e8,
                        address(0xa11ce),
                        address(0xa11ce)
                    )
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoBlueActions.repayAndWithdrawCollateral(MorphoInfo.getMorphoAddress(), MorphoInfo.getMarketParams(1, WBTC, USDC), 1e6, 0, 0e8, address(0xa11ce), address(0xa11ce));"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 2);
        assertEq(result.quarkOperations[0].scriptSources[0], type(MorphoBlueActions).creationCode);
        assertEq(
            result.quarkOperations[0].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "REPAY", "action type is 'REPAY'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0e18;
        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = WBTC_PRICE;
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = wbtc_(1);
        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "WBTC";

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.RepayActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralAssetSymbols: collateralAssetSymbols,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    comet: address(0),
                    price: USDC_PRICE,
                    token: usdc_(1),
                    morpho: MorphoInfo.getMorphoAddress(),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(1, "WBTC", "USDC"))
                })
            ),
            "action context encoded from RepayActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometRepayWithBridge() public {
        QuarkBuilder builder = new QuarkBuilder();

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.2e6});

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(4e6, 0, 0, 0), // 4 USDC on mainnet
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0), // no assets on base
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });

        QuarkBuilder.BuilderResult memory result = builder.morphoRepay(
            repayIntent_(
                8453,
                "USDC", // repaying 2 USDC, bridged from mainnet to base
                2e6,
                "WETH",
                0e18
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        address paycallAddress = paycallUsdc_(1);
        address paycallAddressBase = paycallUsdc_(8453);
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);
        address morphoBlueActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoBlueActions).creationCode);

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
                    2.2e6, // 2e6 repaid + 0.2e6 max cost on Base
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                ),
                0.1e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(0xBd3fa81B58Ba92a82136038B25aDec7066af3155, 2.2e6, 6, 0xa11ce, USDC_1)), 0.1e6);"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 2);
        assertEq(result.quarkOperations[0].scriptSources[0], type(CCTPBridgeActions).creationCode);
        assertEq(
            result.quarkOperations[0].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
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
                morphoBlueActionsAddress,
                abi.encodeCall(
                    MorphoBlueActions.repayAndWithdrawCollateral,
                    (
                        MorphoInfo.getMorphoAddress(),
                        MorphoInfo.getMarketParams(8453, "WETH", "USDC"),
                        2e6,
                        0,
                        0e18,
                        address(0xa11ce),
                        address(0xa11ce)
                    )
                ),
                0.2e6
            ),
            "calldata is Paycall.run(MorphoBlueActions.repayAndWithdrawCollateral(MorphoInfo.getMorphoAddress(), MorphoInfo.getMarketParams(8453, WETH, USDC), 1e6, 0, 0e18, address(0xa11ce), address(0xa11ce));"
        );
        assertEq(result.quarkOperations[1].scriptSources.length, 2);
        assertEq(result.quarkOperations[1].scriptSources[0], type(MorphoBlueActions).creationCode);
        assertEq(
            result.quarkOperations[1].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
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
                    amount: 2.2e6,
                    assetSymbol: "USDC",
                    bridgeType: Actions.BRIDGE_TYPE_CCTP,
                    chainId: 1,
                    destinationChainId: 8453,
                    price: USDC_PRICE,
                    recipient: address(0xa11ce),
                    token: usdc_(1)
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        // second action
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[1].actionType, "REPAY", "action type is 'REPAY'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 0.2e6, "payment should have max cost of 0.2e6");

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0e18;
        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = WETH_PRICE;
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = weth_(8453);
        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "WETH";

        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.RepayActionContext({
                    amount: 2e6,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    collateralAmounts: collateralAmounts,
                    collateralAssetSymbols: collateralAssetSymbols,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    comet: address(0),
                    price: USDC_PRICE,
                    token: usdc_(8453),
                    morpho: MorphoInfo.getMorphoAddress(),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(8453, "WETH", "USDC"))
                })
            ),
            "action context encoded from RepayActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometRepayMax() public {
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});

        MorphoBluePortfolio[] memory morphoBluePortfolios = new MorphoBluePortfolio[](1);
        morphoBluePortfolios[0] = MorphoBluePortfolio({
            marketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(1, "WBTC", "USDC")),
            loanToken: "USDC",
            collateralToken: "WBTC",
            borrowedBalance: 10e6,
            borrowedShares: 5e18, // Random shares number for unit test
            collateralBalance: 1e8
        });

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](1);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(20e6, 0, 0, 0), // has 20 USDC
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: morphoBluePortfolios
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoRepay(
            repayIntent_(
                1,
                "USDC",
                type(uint256).max, // repaying max (all 10 USDC)
                "WBTC",
                0e8 // no collateral withdrawal
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        address paycallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        address morphoBlueActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoBlueActions).creationCode);

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
                morphoBlueActionsAddress,
                abi.encodeCall(
                    MorphoBlueActions.repayAndWithdrawCollateral,
                    (
                        MorphoInfo.getMorphoAddress(),
                        MorphoInfo.getMarketParams(1, "WBTC", "USDC"),
                        0e6,
                        5e18,
                        0e8,
                        address(0xa11ce),
                        address(0xa11ce)
                    ) // Repaying in shares
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoBlueActions.repayAndWithdrawCollateral(MorphoInfo.getMorphoAddress(), MorphoInfo.getMarketParams(1, WBTC, USDC), 0e6, 5e18, 0e8, address(0xa11ce), address(0xa11ce));"
        );

        assertEq(result.quarkOperations[0].scriptSources.length, 2);
        assertEq(result.quarkOperations[0].scriptSources[0], type(MorphoBlueActions).creationCode);
        assertEq(
            result.quarkOperations[0].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "REPAY", "action type is 'REPAY'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment should have max cost of 0.1e6");

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0e8;
        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = WBTC_PRICE;
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = wbtc_(1);
        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "WBTC";

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.RepayActionContext({
                    amount: type(uint256).max,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralAssetSymbols: collateralAssetSymbols,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    comet: address(0),
                    price: USDC_PRICE,
                    token: usdc_(1),
                    morpho: MorphoInfo.getMorphoAddress(),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(1, "WBTC", "USDC"))
                })
            ),
            "action context encoded from RepayActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testCometRepayMaxWithBridge() public {
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.1e6});

        MorphoBluePortfolio[] memory morphoBluePortfolios = new MorphoBluePortfolio[](1);
        morphoBluePortfolios[0] = MorphoBluePortfolio({
            marketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(8453, "WETH", "USDC")),
            loanToken: "USDC",
            collateralToken: "WETH",
            borrowedBalance: 10e6,
            borrowedShares: 5e18, // Random shares number for unit test
            collateralBalance: 1e8
        });

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(50e6, 0, 0, 0), // has 50 USDC
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: emptyMorphoBluePortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0), // has 0 USDC on base
            cometPortfolios: emptyCometPortfolios_(),
            morphoBluePortfolios: morphoBluePortfolios
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoRepay(
            repayIntent_(
                8453,
                "USDC",
                type(uint256).max, // repaying max (all 10 USDC)
                "WETH",
                0e18
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);
        address morphoBlueActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoBlueActions).creationCode);
        address paycallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        address paycallAddressBase = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
        );

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
                    10.11e6, // 10e6 repaid + .1% buffer + 0.1e6 max cost on Base
                    6,
                    bytes32(uint256(uint160(0xa11ce))),
                    usdc_(1)
                ),
                0.1e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(0xBd3fa81B58Ba92a82136038B25aDec7066af3155, 10.11e6, 6, 0xa11ce, USDC_1)), 0.1e6);"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 2);
        assertEq(result.quarkOperations[0].scriptSources[0], type(CCTPBridgeActions).creationCode);
        assertEq(
            result.quarkOperations[0].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
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
                morphoBlueActionsAddress,
                abi.encodeCall(
                    MorphoBlueActions.repayAndWithdrawCollateral,
                    (
                        MorphoInfo.getMorphoAddress(),
                        MorphoInfo.getMarketParams(8453, "WETH", "USDC"),
                        0e6,
                        5e18,
                        0e8,
                        address(0xa11ce),
                        address(0xa11ce)
                    ) // Repaying in shares
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoBlueActions.repayAndWithdrawCollateral(MorphoInfo.getMorphoAddress(), MorphoInfo.getMarketParams(8453, WETH, USDC), 0e6, 5e18, 0e8, address(0xa11ce), address(0xa11ce));"
        );

        assertEq(result.quarkOperations[1].scriptSources.length, 2);
        assertEq(result.quarkOperations[1].scriptSources[0], type(MorphoBlueActions).creationCode);
        assertEq(
            result.quarkOperations[1].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
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
                    amount: 10.11e6,
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
        assertEq(result.actions[1].actionType, "REPAY", "action type is 'REPAY'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 0.1e6, "payment should have max cost of 0.1e6");

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 0e18;
        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = WETH_PRICE;
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = weth_(8453);
        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "WETH";

        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.RepayActionContext({
                    amount: type(uint256).max,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    collateralAmounts: collateralAmounts,
                    collateralAssetSymbols: collateralAssetSymbols,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    comet: address(0),
                    price: USDC_PRICE,
                    token: usdc_(8453),
                    morpho: MorphoInfo.getMorphoAddress(),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(8453, "WETH", "USDC"))
                })
            ),
            "action context encoded from RepayActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }
}
