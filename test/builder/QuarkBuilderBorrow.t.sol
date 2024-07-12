// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilderTest, Accounts, PaymentInfo, QuarkBuilder} from "test/builder/lib/QuarkBuilderTest.sol";

import {Actions} from "src/builder/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {CometSupplyMultipleAssetsAndBorrow} from "src/DeFiScripts.sol";
import {Paycall} from "src/Paycall.sol";
import {Strings} from "src/builder/Strings.sol";

contract QuarkBuilderBorrowTest is Test, QuarkBuilderTest {
    uint256 constant BLOCK_TIMESTAMP = 123_456_789;
    address constant COMET = address(0xc3);

    function borrowIntent_(
        uint256 amount,
        string memory assetSymbol,
        uint256 chainId,
        uint256[] memory collateralAmounts,
        string[] memory collateralAssetSymbols
    ) internal pure returns (QuarkBuilder.CometBorrowIntent memory) {
        return QuarkBuilder.CometBorrowIntent({
            amount: amount,
            assetSymbol: assetSymbol,
            blockTimestamp: BLOCK_TIMESTAMP,
            borrower: address(0xa11ce),
            chainId: chainId,
            collateralAmounts: collateralAmounts,
            collateralAssetSymbols: collateralAssetSymbols,
            comet: COMET
        });
    }

    function stringArray(string memory string0, string memory string1, string memory string2, string memory string3)
        internal
        pure
        returns (string[] memory)
    {
        string[] memory strings = new string[](4);
        strings[0] = string0;
        strings[1] = string1;
        strings[2] = string2;
        strings[3] = string3;
        return strings;
    }

    function uintArray(uint256 uint0, uint256 uint1, uint256 uint2, uint256 uint3)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory uints = new uint256[](4);
        uints[0] = uint0;
        uints[1] = uint1;
        uints[2] = uint2;
        uints[3] = uint3;
        return uints;
    }

    struct ChainPortfolio {
        uint256 chainId;
        address account;
        uint96 nextNonce;
        string[] assetSymbols;
        uint256[] assetBalances;
    }

    function chainAccountsFromChainPortfolios(ChainPortfolio[] memory chainPortfolios)
        internal
        pure
        returns (Accounts.ChainAccounts[] memory)
    {
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](chainPortfolios.length);
        for (uint256 i = 0; i < chainPortfolios.length; ++i) {
            chainAccountsList[i] = Accounts.ChainAccounts({
                chainId: chainPortfolios[i].chainId,
                quarkStates: quarkStates_(chainPortfolios[i].account, chainPortfolios[i].nextNonce),
                assetPositionsList: assetPositionsForAssets(
                    chainPortfolios[i].chainId,
                    chainPortfolios[i].account,
                    chainPortfolios[i].assetSymbols,
                    chainPortfolios[i].assetBalances
                    )
            });
        }

        return chainAccountsList;
    }

    function assetPositionsForAssets(
        uint256 chainId,
        address account,
        string[] memory assetSymbols,
        uint256[] memory assetBalances
    ) internal pure returns (Accounts.AssetPositions[] memory) {
        Accounts.AssetPositions[] memory assetPositionsList = new Accounts.AssetPositions[](assetSymbols.length);

        for (uint256 i = 0; i < assetSymbols.length; ++i) {
            (address asset, uint256 decimals, uint256 price) = assetInfo(assetSymbols[i], chainId);
            assetPositionsList[i] = Accounts.AssetPositions({
                asset: asset,
                symbol: assetSymbols[i],
                decimals: decimals,
                usdPrice: price,
                accountBalances: accountBalances_(account, assetBalances[i])
            });
        }

        return assetPositionsList;
    }

    function assetInfo(string memory assetSymbol, uint256 chainId) internal pure returns (address, uint256, uint256) {
        if (Strings.stringEq(assetSymbol, "USDC")) {
            return (usdc_(chainId), 6, 1e8);
        } else if (Strings.stringEq(assetSymbol, "USDT")) {
            return (usdt_(chainId), 6, 1e8);
        } else if (Strings.stringEq(assetSymbol, "WETH")) {
            return (weth_(chainId), 18, 3000e8);
        } else if (Strings.stringEq(assetSymbol, "LINK")) {
            return (link_(chainId), 18, 14e8);
        } else {
            revert("unknown assetSymbol");
        }
    }

    function testBorrowInvalidInput() public {
        uint256[] memory collateralAmounts = new uint256[](2);
        collateralAmounts[0] = 1e18;
        collateralAmounts[1] = 1e18;

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "LINK";

        QuarkBuilder builder = new QuarkBuilder();

        vm.expectRevert(QuarkBuilder.InvalidInput.selector);

        builder.cometBorrow(
            borrowIntent_(1e6, "USDC", 1, collateralAmounts, collateralAssetSymbols),
            chainAccountsList_(3e6),
            paymentUsd_()
        );
    }

    function testBorrowFundsUnavailable() public {
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e18;

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "LINK";

        QuarkBuilder builder = new QuarkBuilder();

        vm.expectRevert(abi.encodeWithSelector(QuarkBuilder.FundsUnavailable.selector, "LINK", 1e18, 0));

        builder.cometBorrow(
            borrowIntent_(1e6, "USDC", 1, collateralAmounts, collateralAssetSymbols),
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsd_()
        );
    }

    function testBorrow() public {
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e18;

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "LINK";

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(0, 0, 10e18, 0) // user has 10 LINK
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(0, 0, 0, 0)
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometBorrow(
            borrowIntent_(
                1e6,
                "USDC",
                1,
                collateralAmounts, // [1e18]
                collateralAssetSymbols // [LINK]
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
                                keccak256(type(CometSupplyMultipleAssetsAndBorrow).creationCode)
                            )
                        )
                    )
                )
            ),
            "script address is correct given the code jar address on mainnet"
        );
        address[] memory collateralAssets = new address[](1);
        collateralAssets[0] = link_(1);
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(
                CometSupplyMultipleAssetsAndBorrow.run, (COMET, collateralAssets, collateralAmounts, usdc_(1), 1e6)
            ),
            "calldata is CometSupplyMultipleAssetsAndBorrow.run(COMET, [LINK], [1e18], USDC, 1e6);"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 1);
        assertEq(result.quarkOperations[0].scriptSources[0], type(CometSupplyMultipleAssetsAndBorrow).creationCode);
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");

        uint256[] memory collateralAssetPrices = new uint256[](1);
        collateralAssetPrices[0] = 14e8;

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralAssetPrices: collateralAssetPrices,
                    collateralAssets: collateralAssets,
                    comet: COMET,
                    price: 1e8,
                    token: usdc_(1)
                })
            ),
            "action context encoded from BorrowActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBorrowWithPaycall() public {
        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "LINK";

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e18;

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(1e6, 0, 10e18, 0) // user has 1 USDC, 10 LINK
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(0, 0, 0, 0)
        });

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometBorrow(
            borrowIntent_(
                1e6,
                "USDC",
                1,
                collateralAmounts, // [1e18]
                collateralAssetSymbols // [LINK]
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        address cometSupplyMultipleAssetsAndBorrowAddress =
            CodeJarHelper.getCodeAddress(type(CometSupplyMultipleAssetsAndBorrow).creationCode);
        address paycallAddress = paycallUsdc_(1);

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            paycallAddress,
            "script address is correct given the code jar address on mainnet"
        );

        address[] memory collateralAssets = new address[](1);
        collateralAssets[0] = link_(1);

        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cometSupplyMultipleAssetsAndBorrowAddress,
                abi.encodeWithSelector(
                    CometSupplyMultipleAssetsAndBorrow.run.selector,
                    COMET,
                    collateralAssets,
                    collateralAmounts,
                    usdc_(1),
                    1e6
                ),
                0.1e6
            ),
            "calldata is Paycall.run(CometSupplyMultipleAssetsAndBorrow.run(COMET, [LINK_1], [1e18], USDC_1, 1e6), 0.1e6);"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 2);
        assertEq(result.quarkOperations[0].scriptSources[0], type(CometSupplyMultipleAssetsAndBorrow).creationCode);
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
        assertEq(result.actions[0].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");

        uint256[] memory collateralAssetPrices = new uint256[](1);
        collateralAssetPrices[0] = 14e8;

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralAssetPrices: collateralAssetPrices,
                    collateralAssets: collateralAssets,
                    comet: COMET,
                    price: 1e8,
                    token: usdc_(1)
                })
            ),
            "action context encoded from BorrowActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBorrowPayFromBorrow() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6}); // action costs .5 USDC

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e18;

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "LINK";

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(0, 0, 10e18, 0) // user has 10 LINK and 0 USDC
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(0, 0, 0, 0)
        });

        QuarkBuilder.BuilderResult memory result = builder.cometBorrow(
            borrowIntent_(
                1e6,
                "USDC",
                1,
                collateralAmounts, // [1e18]
                collateralAssetSymbols // [LINK]
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts) // user is paying with borrowed USDC
        );

        address cometSupplyMultipleAssetsAndBorrowAddress =
            CodeJarHelper.getCodeAddress(type(CometSupplyMultipleAssetsAndBorrow).creationCode);
        address paycallAddress = paycallUsdc_(1);

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        address[] memory collateralAssets = new address[](1);
        collateralAssets[0] = link_(1);

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
                cometSupplyMultipleAssetsAndBorrowAddress,
                abi.encodeWithSelector(
                    CometSupplyMultipleAssetsAndBorrow.run.selector,
                    COMET,
                    collateralAssets,
                    collateralAmounts,
                    usdc_(1),
                    1e6
                ),
                0.5e6
            ),
            "calldata is Paycall.run(CometSupplyMultipleAssetsAndBorrow.run.selector, (COMET, [LINK_1], [1e18], USDC_1, 1e6), .5e6);"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 2);
        assertEq(result.quarkOperations[0].scriptSources[0], type(CometSupplyMultipleAssetsAndBorrow).creationCode);
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
        assertEq(result.actions[0].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment max is set to .5e6 in this test case");

        uint256[] memory collateralAssetPrices = new uint256[](1);
        collateralAssetPrices[0] = 14e8;

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralAssetPrices: collateralAssetPrices,
                    collateralAssets: collateralAssets,
                    comet: COMET,
                    price: 1e8,
                    token: usdc_(1)
                })
            ),
            "action context encoded from BorrowActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBorrowWithBridgedPaymentToken() public {
        QuarkBuilder builder = new QuarkBuilder();

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e6}); // max cost on base is 1 USDC

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "LINK";

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e18;

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(3e6, 0, 0, 0) // 3 USDC on mainnet
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(0, 0, 5e18, 0)
        });

        QuarkBuilder.BuilderResult memory result = builder.cometBorrow(
            borrowIntent_(
                1e6,
                "USDT",
                8453,
                collateralAmounts, // [1e18]
                collateralAssetSymbols // [LINK]
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        address paycallAddress = paycallUsdc_(1);
        address paycallAddressBase = paycallUsdc_(8453);
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);
        address cometSupplyMultipleAssetsAndBorrowAddress =
            CodeJarHelper.getCodeAddress(type(CometSupplyMultipleAssetsAndBorrow).creationCode);

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

        address[] memory collateralAssets = new address[](1);
        collateralAssets[0] = link_(8453);

        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cometSupplyMultipleAssetsAndBorrowAddress,
                abi.encodeWithSelector(
                    CometSupplyMultipleAssetsAndBorrow.run.selector,
                    COMET,
                    collateralAssets,
                    collateralAmounts,
                    usdt_(8453),
                    1e6
                ),
                1e6
            ),
            "calldata is Paycall.run(CometSupplyMultipleAssetsAndBorrow.run(COMET, [LINK_8453], [1e18], USDT_8453, 1e6), 1e6);"
        );
        assertEq(result.quarkOperations[1].scriptSources.length, 2);
        assertEq(result.quarkOperations[1].scriptSources[0], type(CometSupplyMultipleAssetsAndBorrow).creationCode);
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
                    amount: 1e6,
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
        assertEq(result.actions[1].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 1e6, "payment should have max cost of 1e6");

        uint256[] memory collateralAssetPrices = new uint256[](1);
        collateralAssetPrices[0] = 14e8;

        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    chainId: 8453,
                    collateralAmounts: collateralAmounts,
                    collateralAssetPrices: collateralAssetPrices,
                    collateralAssets: collateralAssets,
                    comet: COMET,
                    price: 1e8,
                    token: usdt_(8453)
                })
            ),
            "action context encoded from BorrowActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBorrowWithBridgedcollateralAsset() public {
        QuarkBuilder builder = new QuarkBuilder();

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.2e6});

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "USDC"; // supplying 2 USDC as collateral

        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 2e6;

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(4e6, 0, 0, 0) // 4 USDC on mainnet
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: uintArray(0, 0, 0, 0) // no assets on base
        });

        QuarkBuilder.BuilderResult memory result = builder.cometBorrow(
            borrowIntent_(
                1e18,
                "WETH", // borrowing WETH
                8453,
                collateralAmounts, // [2e6]
                collateralAssetSymbols // [USDC]
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts)
        );

        address paycallAddress = paycallUsdc_(1);
        address paycallAddressBase = paycallUsdc_(8453);
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);
        address cometSupplyMultipleAssetsAndBorrowAddress =
            CodeJarHelper.getCodeAddress(type(CometSupplyMultipleAssetsAndBorrow).creationCode);

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
                    2.2e6, // 2e6 supplied + 0.2e6 max cost on Base
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

        address[] memory collateralAssets = new address[](1);
        collateralAssets[0] = usdc_(8453);

        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cometSupplyMultipleAssetsAndBorrowAddress,
                abi.encodeWithSelector(
                    CometSupplyMultipleAssetsAndBorrow.run.selector,
                    COMET,
                    collateralAssets,
                    collateralAmounts,
                    weth_(8453),
                    1e18
                ),
                0.2e6
            ),
            "calldata is Paycall.run(CometSupplyMultipleAssetsAndBorrow.run(COMET, [USDC_8453], [2e6], WETH_8453, 1e18), 0.2e6);"
        );
        assertEq(result.quarkOperations[1].scriptSources.length, 2);
        assertEq(result.quarkOperations[1].scriptSources[0], type(CometSupplyMultipleAssetsAndBorrow).creationCode);
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
        assertEq(result.actions[1].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 0.2e6, "payment should have max cost of 0.2e6");

        uint256[] memory collateralAssetPrices = new uint256[](1);
        collateralAssetPrices[0] = 1e8;

        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e18,
                    chainId: 8453,
                    collateralAmounts: collateralAmounts,
                    collateralAssetPrices: collateralAssetPrices,
                    collateralAssets: collateralAssets,
                    comet: COMET,
                    price: 3000e8,
                    token: weth_(8453)
                })
            ),
            "action context encoded from BorrowActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }
}
