// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Arrays} from "test/builder/lib/Arrays.sol";
import {QuarkBuilderTest, Accounts, PaymentInfo, QuarkBuilder} from "test/builder/lib/QuarkBuilderTest.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";
import {MorphoActionsBuilder} from "src/builder/actions/MorphoActionsBuilder.sol";
import {Actions} from "src/builder/actions/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {MorphoActions} from "src/MorphoScripts.sol";
import {Paycall} from "src/Paycall.sol";
import {Strings} from "src/builder/Strings.sol";
import {Multicall} from "src/Multicall.sol";
import {WrapperActions} from "src/WrapperScripts.sol";
import {MorphoInfo} from "src/builder/MorphoInfo.sol";
import {TokenWrapper} from "src/builder/TokenWrapper.sol";

contract QuarkBuilderMorphoBorrowTest is Test, QuarkBuilderTest {
    function borrowIntent_(
        uint256 chainId,
        string memory assetSymbol,
        uint256 amount,
        string memory collateralAssetSymbol,
        uint256 collateralAmount
    ) internal pure returns (MorphoActionsBuilder.MorphoBorrowIntent memory) {
        return borrowIntent_({
            chainId: chainId,
            assetSymbol: assetSymbol,
            amount: amount,
            collateralAssetSymbol: collateralAssetSymbol,
            collateralAmount: collateralAmount,
            borrower: address(0xa11ce)
        });
    }

    function borrowIntent_(
        uint256 chainId,
        string memory assetSymbol,
        uint256 amount,
        string memory collateralAssetSymbol,
        uint256 collateralAmount,
        address borrower
    ) internal pure returns (MorphoActionsBuilder.MorphoBorrowIntent memory) {
        return MorphoActionsBuilder.MorphoBorrowIntent({
            amount: amount,
            assetSymbol: assetSymbol,
            blockTimestamp: BLOCK_TIMESTAMP,
            borrower: borrower,
            chainId: chainId,
            collateralAmount: collateralAmount,
            collateralAssetSymbol: collateralAssetSymbol
        });
    }

    function testBorrowInvalidMarketParams() public {
        QuarkBuilder builder = new QuarkBuilder();
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 1e8, 1e18),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: BOB_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        // Pair not exist in known Morpho markets
        vm.expectRevert(MorphoInfo.MorphoMarketNotFound.selector);
        builder.morphoBorrow(
            borrowIntent_(1, "USDC", 1e6, "WETH", 1e18),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsd_()
        );
    }

    function testBorrowFundsUnavailable() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "WBTC", 1e8, 0));
        builder.morphoBorrow(
            borrowIntent_(1, "USDC", 1e6, "WBTC", 1e8),
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsd_()
        );
    }

    function testBorrowSuccess() public {
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 1e8, 0), // user has 1 WBTC
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: BOB_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoBorrow(
            borrowIntent_(1, "USDC", 1e6, "WBTC", 1e8), chainAccountsFromChainPortfolios(chainPortfolios), paymentUsd_()
        );
        address MorphoActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoActions).creationCode);
        // Check the quark operations
        assertEq(result.paymentCurrency, "usd", "usd currency");
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            MorphoActionsAddress,
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(
                MorphoActions.supplyCollateralAndBorrow,
                (MorphoInfo.getMorphoAddress(1), MorphoInfo.getMarketParams(1, "WBTC", "USDC"), 1e8, 1e6)
            ),
            "calldata is MorphoActions.supplyCollateralAndBorrow(MorphoInfo.getMorphoAddress(1), MorphoInfo.getMarketParams(1, WBTC, USDC), 1e8, 1e6, address(0xal1ce), address(0xal1ce));"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 1);
        assertEq(result.quarkOperations[0].scriptSources[0], type(MorphoActions).creationCode);
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "MORPHO_BORROW", "action type is 'MORPHO_BORROW'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoBorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmount: 1e8,
                    collateralTokenPrice: WBTC_PRICE,
                    collateralToken: wbtc_(1),
                    collateralAssetSymbol: "WBTC",
                    price: USDC_PRICE,
                    token: usdc_(1),
                    morpho: MorphoInfo.getMorphoAddress(1),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(1, "WBTC", "USDC"))
                })
            ),
            "action context encoded from MorphoBorrowActionContext"
        );

        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBorrowWithAutoWrapper() public {
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xb0b),
            nonceSecret: BOB_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "ETH", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "ETH", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 10e18, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoBorrow(
            borrowIntent_(8453, "USDC", 1e6, "WETH", 1e18),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        address multicallAddress = CodeJarHelper.getCodeAddress(type(Multicall).creationCode);
        address wrapperActionsAddress = CodeJarHelper.getCodeAddress(type(WrapperActions).creationCode);
        address MorphoActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoActions).creationCode);
        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one merged operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            multicallAddress,
            "script address is correct given the code jar address on mainnet"
        );
        address[] memory callContracts = new address[](2);
        callContracts[0] = wrapperActionsAddress;
        callContracts[1] = MorphoActionsAddress;
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encodeWithSelector(
            WrapperActions.wrapETH.selector, TokenWrapper.getKnownWrapperTokenPair(8453, "WETH").wrapper, 1e18
        );
        callDatas[1] = abi.encodeCall(
            MorphoActions.supplyCollateralAndBorrow,
            (MorphoInfo.getMorphoAddress(8453), MorphoInfo.getMarketParams(8453, "WETH", "USDC"), 1e18, 1e6)
        );

        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
            "calldata is Multicall.run([wrapperActionsAddress, MorphoActionsAddress], [WrapperActions.wrapWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 10e18), MorphoActions.supplyCollateralAndBorrow(MorphoInfo.getMorphoAddress(8453), MorphoInfo.getMarketParams(8453, WETH, USDC), 1e18, 1e6, address(0xa11ce), address(0xa11ce))"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 3);
        assertEq(result.quarkOperations[0].scriptSources[0], type(WrapperActions).creationCode);
        assertEq(result.quarkOperations[0].scriptSources[1], type(MorphoActions).creationCode);
        assertEq(result.quarkOperations[0].scriptSources[2], type(Multicall).creationCode);
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "MORPHO_BORROW", "action type is 'MORPHO_BORROW'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoBorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    collateralAmount: 1e18,
                    collateralTokenPrice: WETH_PRICE,
                    collateralToken: weth_(8453),
                    collateralAssetSymbol: "WETH",
                    price: USDC_PRICE,
                    token: usdc_(8453),
                    morpho: MorphoInfo.getMorphoAddress(8453),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(8453, "WETH", "USDC"))
                })
            ),
            "action context encoded from MorphoBorrowActionContext"
        );

        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBorrowWithPaycall() public {
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(1e6, 0, 1e8, 0), // user has 1 WBTC and 1USDC for payment
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: BOB_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoBorrow(
            borrowIntent_(1, "USDC", 1e6, "WBTC", 1e8),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        address MorphoActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoActions).creationCode);
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
                MorphoActionsAddress,
                abi.encodeCall(
                    MorphoActions.supplyCollateralAndBorrow,
                    (MorphoInfo.getMorphoAddress(1), MorphoInfo.getMarketParams(1, "WBTC", "USDC"), 1e8, 1e6)
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoActions.supplyCollateralAndBorrow(MorphoInfo.getMorphoAddress(1), MorphoInfo.getMarketParams(1, WBTC, USDC), 1e8, 1e6, address(0xa11ce), address(0xa11ce));"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 2);
        assertEq(result.quarkOperations[0].scriptSources[0], type(MorphoActions).creationCode);
        assertEq(
            result.quarkOperations[0].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "MORPHO_BORROW", "action type is 'MORPHO_BORROW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoBorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmount: 1e8,
                    collateralTokenPrice: WBTC_PRICE,
                    collateralToken: wbtc_(1),
                    collateralAssetSymbol: "WBTC",
                    price: USDC_PRICE,
                    token: usdc_(1),
                    morpho: MorphoInfo.getMorphoAddress(1),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(1, "WBTC", "USDC"))
                })
            ),
            "action context encoded from MorphoBorrowActionContext"
        );

        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBorrowPayFromBorrow() public {
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 1e8, 0), // user has 1 WBTC but with 0 USDC
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: BOB_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoBorrow(
            borrowIntent_(1, "USDC", 1e6, "WBTC", 1e8),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        address MorphoActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoActions).creationCode);
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
                MorphoActionsAddress,
                abi.encodeCall(
                    MorphoActions.supplyCollateralAndBorrow,
                    (MorphoInfo.getMorphoAddress(1), MorphoInfo.getMarketParams(1, "WBTC", "USDC"), 1e8, 1e6)
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoActions.supplyCollateralAndBorrow(MorphoInfo.getMorphoAddress(), MorphoInfo.getMarketParams(1, WBTC, USDC), 1e8, 1e6, address(0xa11ce), address(0xa11ce));"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 2);
        assertEq(result.quarkOperations[0].scriptSources[0], type(MorphoActions).creationCode);
        assertEq(
            result.quarkOperations[0].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "MORPHO_BORROW", "action type is 'MORPHO_MORPHO_BORROW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoBorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmount: 1e8,
                    collateralTokenPrice: WBTC_PRICE,
                    collateralToken: wbtc_(1),
                    collateralAssetSymbol: "WBTC",
                    price: USDC_PRICE,
                    token: usdc_(1),
                    morpho: MorphoInfo.getMorphoAddress(1),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(1, "WBTC", "USDC"))
                })
            ),
            "action context encoded from MorphoBorrowActionContext"
        );

        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBorrowWithBridgedPaymentToken() public {
        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "cbETH", "WETH"),
            assetBalances: Arrays.uintArray(5e6, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: BOB_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "cbETH", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 1e18, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e6}); // max cost on base is 1 USDC

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoBorrow(
            borrowIntent_({
                chainId: 8453,
                assetSymbol: "WETH",
                amount: 0.2e18,
                collateralAssetSymbol: "cbETH",
                collateralAmount: 1e18,
                borrower: address(0xb0b)
            }),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        address paycallAddress = paycallUsdc_(1);
        address paycallAddressBase = paycallUsdc_(8453);
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);
        address MorphoActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoActions).creationCode);

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
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                ),
                0.1e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(0xBd3fa81B58Ba92a82136038B25aDec7066af3155, 1e6, 6, 0xb0b, USDC_1)), 0.1e6);"
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
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

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
                MorphoActionsAddress,
                abi.encodeCall(
                    MorphoActions.supplyCollateralAndBorrow,
                    (MorphoInfo.getMorphoAddress(8453), MorphoInfo.getMarketParams(8453, "cbETH", "WETH"), 1e18, 0.2e18)
                ),
                1e6
            ),
            "calldata is Paycall.run(MorphoActions.supplyCollateralAndBorrow(MorphoInfo.getMorphoAddress(8453), MorphoInfo.getMarketParams(8453, cbETH, WETH), 1e18, 0.2e18, address(0xa11ce), address(0xa11ce));"
        );
        assertEq(result.quarkOperations[1].scriptSources.length, 2);
        assertEq(result.quarkOperations[1].scriptSources[0], type(MorphoActions).creationCode);
        assertEq(
            result.quarkOperations[1].scriptSources[1],
            abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[1].nonce, BOB_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[1].isReplayable, false, "isReplayable is false");

        // Check the actions
        assertEq(result.actions.length, 2, "two actions");
        // first action
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment should have max cost of 0.1e6");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    price: USDC_PRICE,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    inputAmount: 1e6,
                    outputAmount: 1e6,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        // second action
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "MORPHO_BORROW", "action type is 'MORPHO_BORROW'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 1e6, "payment should have max cost of 1e6");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.MorphoBorrowActionContext({
                    amount: 0.2e18,
                    assetSymbol: "WETH",
                    chainId: 8453,
                    collateralAmount: 1e18,
                    collateralTokenPrice: CBETH_PRICE,
                    collateralToken: cbEth_(8453),
                    collateralAssetSymbol: "cbETH",
                    price: WETH_PRICE,
                    token: weth_(8453),
                    morpho: MorphoInfo.getMorphoAddress(8453),
                    morphoMarketId: MorphoInfo.marketId(MorphoInfo.getMarketParams(8453, "cbETH", "WETH"))
                })
            ),
            "action context encoded from MorphoBorrowActionContext"
        );

        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testMorphoBorrowMaxCostTooHighForBridgePaymentToken() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6}); // action costs .5 USDC

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](1);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "WBTC", "WETH"),
            assetBalances: Arrays.uintArray(0.4e6, 0, 2e8, 1e18), // user does not have enough USDC
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        vm.expectRevert(abi.encodeWithSelector(Actions.NotEnoughFundsToBridge.selector, "usdc", 0.1e6, 0.1e6));

        builder.morphoBorrow(
            borrowIntent_(1, "WETH", 1e18, "WBTC", 0),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );
    }
}
