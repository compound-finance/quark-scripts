// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Arrays} from "test/builder/lib/Arrays.sol";
import {QuarkBuilderTest, Accounts, PaymentInfo, QuarkBuilder} from "test/builder/lib/QuarkBuilderTest.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";
import {CometActionsBuilder} from "src/builder/actions/CometActionsBuilder.sol";
import {Actions} from "src/builder/actions/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {CometSupplyMultipleAssetsAndBorrow} from "src/DeFiScripts.sol";
import {Paycall} from "src/Paycall.sol";
import {Strings} from "src/builder/Strings.sol";
import {Multicall} from "src/Multicall.sol";
import {WrapperActions} from "src/WrapperScripts.sol";

contract QuarkBuilderCometBorrowTest is Test, QuarkBuilderTest {
    function borrowIntent_(
        uint256 amount,
        string memory assetSymbol,
        uint256 chainId,
        uint256[] memory collateralAmounts,
        string[] memory collateralAssetSymbols
    ) internal pure returns (CometActionsBuilder.CometBorrowIntent memory) {
        return CometActionsBuilder.CometBorrowIntent({
            amount: amount,
            assetSymbol: assetSymbol,
            blockTimestamp: BLOCK_TIMESTAMP,
            borrower: address(0xa11ce),
            chainId: chainId,
            collateralAmounts: collateralAmounts,
            collateralAssetSymbols: collateralAssetSymbols,
            comet: cometUsdc_(1),
            preferAcross: false
        });
    }

    function testBorrowInvalidInput() public {
        uint256[] memory collateralAmounts = new uint256[](2);
        collateralAmounts[0] = 1e18;
        collateralAmounts[1] = 1e18;

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "LINK";

        QuarkBuilder builder = new QuarkBuilder();

        vm.expectRevert(QuarkBuilderBase.InvalidInput.selector);

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

        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "LINK", 1e18, 0));

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
            nonceSecret: bytes32(uint256(12)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 10e18, 0), // user has 10 LINK
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: bytes32(uint256(2)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
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
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = link_(1);
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(
                CometSupplyMultipleAssetsAndBorrow.run,
                (cometUsdc_(1), collateralTokens, collateralAmounts, usdc_(1), 1e6)
            ),
            "calldata is CometSupplyMultipleAssetsAndBorrow.run(COMET_1_USDC, [LINK], [1e18], USDC, 1e6);"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 1);
        assertEq(result.quarkOperations[0].scriptSources[0], type(CometSupplyMultipleAssetsAndBorrow).creationCode);
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, chainPortfolios[0].nonceSecret, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, chainPortfolios[0].nonceSecret, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");

        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = LINK_PRICE;

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    collateralAssetSymbols: collateralAssetSymbols,
                    comet: cometUsdc_(1),
                    price: USDC_PRICE,
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

    function testBorrowWithAutoWrapper() public {
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e18;

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "WETH";

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = weth_(1);

        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = WETH_PRICE;

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: bytes32(uint256(12)),
            assetSymbols: Arrays.stringArray("USDC", "ETH", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 10e18, 0, 0), // user has 10 ETH
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: bytes32(uint256(2)),
            assetSymbols: Arrays.stringArray("USDC", "ETH", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometBorrow(
            borrowIntent_(
                1e6,
                "USDC",
                1,
                collateralAmounts, // [10e18]
                collateralAssetSymbols // [WETH]
            ),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        address multicallAddress = CodeJarHelper.getCodeAddress(type(Multicall).creationCode);
        address wrapperActionsAddress = CodeJarHelper.getCodeAddress(type(WrapperActions).creationCode);
        address cometSupplyMultipleAssetsAndBorrowAddress =
            CodeJarHelper.getCodeAddress(type(CometSupplyMultipleAssetsAndBorrow).creationCode);
        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one merged operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            multicallAddress,
            "script address is correct given the code jar address on mainnet"
        );
        address[] memory callContracts = new address[](2);
        callContracts[0] = wrapperActionsAddress;
        callContracts[1] = cometSupplyMultipleAssetsAndBorrowAddress;
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] =
            abi.encodeWithSelector(WrapperActions.wrapAllETH.selector, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        callDatas[1] = abi.encodeCall(
            CometSupplyMultipleAssetsAndBorrow.run, (cometUsdc_(1), collateralTokens, collateralAmounts, usdc_(1), 1e6)
        );

        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
            "calldata is Multicall.run([wrapperActionsAddress, cometSupplyMultipleAssetsAndBorrowAddress], [WrapperActions.wrapAllETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), CometSupplyMultipleAssetsAndBorrow.run(COMET_1, collateralTokens, collateralAmounts, usdc_(1), 1e6)"
        );
        assertEq(result.quarkOperations[0].scriptSources.length, 3);
        assertEq(result.quarkOperations[0].scriptSources[0], type(WrapperActions).creationCode);
        assertEq(result.quarkOperations[0].scriptSources[1], type(CometSupplyMultipleAssetsAndBorrow).creationCode);
        assertEq(result.quarkOperations[0].scriptSources[2], type(Multicall).creationCode);
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, chainPortfolios[0].nonceSecret, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, chainPortfolios[0].nonceSecret, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    collateralAssetSymbols: collateralAssetSymbols,
                    comet: cometUsdc_(1),
                    price: USDC_PRICE,
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
            nonceSecret: bytes32(uint256(12)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(1e6, 0, 10e18, 0), // user has 1 USDC, 10 LINK
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: bytes32(uint256(2)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
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

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = link_(1);

        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cometSupplyMultipleAssetsAndBorrowAddress,
                abi.encodeWithSelector(
                    CometSupplyMultipleAssetsAndBorrow.run.selector,
                    cometUsdc_(1),
                    collateralTokens,
                    collateralAmounts,
                    usdc_(1),
                    1e6
                ),
                0.1e6
            ),
            "calldata is Paycall.run(CometSupplyMultipleAssetsAndBorrow.run(COMET_1_USDC, [LINK_1], [1e18], USDC_1, 1e6), 0.1e6);"
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
        assertEq(result.quarkOperations[0].nonce, chainPortfolios[0].nonceSecret, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");
        assertEq(result.actions[0].nonceSecret, chainPortfolios[0].nonceSecret, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");

        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = LINK_PRICE;

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    collateralAssetSymbols: collateralAssetSymbols,
                    comet: cometUsdc_(1),
                    price: USDC_PRICE,
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
            nonceSecret: bytes32(uint256(12)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 10e18, 0), // user has 10 LINK and 0 USDC
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nonceSecret: bytes32(uint256(2)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
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

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = link_(1);

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
                    cometUsdc_(1),
                    collateralTokens,
                    collateralAmounts,
                    usdc_(1),
                    1e6
                ),
                0.5e6
            ),
            "calldata is Paycall.run(CometSupplyMultipleAssetsAndBorrow.run.selector, (COMET_1_USDC, [LINK_1], [1e18], USDC_1, 1e6), .5e6);"
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
        assertEq(result.quarkOperations[0].nonce, chainPortfolios[0].nonceSecret, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BORROW", "action type is 'BORROW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment max is set to .5e6 in this test case");
        assertEq(result.actions[0].nonceSecret, chainPortfolios[0].nonceSecret, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");

        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = LINK_PRICE;

        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    collateralAmounts: collateralAmounts,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    collateralAssetSymbols: collateralAssetSymbols,
                    comet: cometUsdc_(1),
                    price: USDC_PRICE,
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
            nonceSecret: bytes32(uint256(12)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(3e6, 0, 0, 0), // 3 USDC on mainnet
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xa11ce),
            nonceSecret: bytes32(uint256(2)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 5e18, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
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
        assertEq(result.quarkOperations[0].nonce, chainPortfolios[0].nonceSecret, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // second operation
        assertEq(
            result.quarkOperations[1].scriptAddress,
            paycallAddressBase,
            "script address[1] has been wrapped with paycall address"
        );

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = link_(8453);

        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cometSupplyMultipleAssetsAndBorrowAddress,
                abi.encodeWithSelector(
                    CometSupplyMultipleAssetsAndBorrow.run.selector,
                    cometUsdc_(1),
                    collateralTokens,
                    collateralAmounts,
                    usdt_(8453),
                    1e6
                ),
                1e6
            ),
            "calldata is Paycall.run(CometSupplyMultipleAssetsAndBorrow.run(COMET_1_USDC, [LINK_8453], [1e18], USDT_8453, 1e6), 1e6);"
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
        assertEq(result.quarkOperations[1].nonce, chainPortfolios[1].nonceSecret, "unexpected nonce");
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
        assertEq(result.actions[0].nonceSecret, chainPortfolios[0].nonceSecret, "unexpected nonce secret");
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
        assertEq(result.actions[1].nonceSecret, chainPortfolios[1].nonceSecret, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");

        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = LINK_PRICE;

        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e6,
                    assetSymbol: "USDT",
                    chainId: 8453,
                    collateralAmounts: collateralAmounts,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    collateralAssetSymbols: collateralAssetSymbols,
                    comet: cometUsdc_(1),
                    price: USDT_PRICE,
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
            nonceSecret: bytes32(uint256(12)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(4e6, 0, 0, 0), // 4 USDC on mainnet
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            // TODO: if want to test different accounts, can set bridge as b0b and send as allice
            account: address(0xa11ce),
            nonceSecret: bytes32(uint256(2)),
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0), // no assets on base
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
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
        assertEq(result.quarkOperations[0].nonce, chainPortfolios[0].nonceSecret, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // second operation
        assertEq(
            result.quarkOperations[1].scriptAddress,
            paycallAddressBase,
            "script address[1] has been wrapped with paycall address"
        );

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = usdc_(8453);

        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                cometSupplyMultipleAssetsAndBorrowAddress,
                abi.encodeWithSelector(
                    CometSupplyMultipleAssetsAndBorrow.run.selector,
                    cometUsdc_(1),
                    collateralTokens,
                    collateralAmounts,
                    weth_(8453),
                    1e18
                ),
                0.2e6
            ),
            "calldata is Paycall.run(CometSupplyMultipleAssetsAndBorrow.run(COMET_1_USDC, [USDC_8453], [2e6], WETH_8453, 1e18), 0.2e6);"
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
        assertEq(result.quarkOperations[1].nonce, chainPortfolios[1].nonceSecret, "unexpected nonce");
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
        assertEq(result.actions[0].nonceSecret, chainPortfolios[0].nonceSecret, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    price: USDC_PRICE,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    inputAmount: 2.2e6,
                    outputAmount: 2.2e6,
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
        assertEq(result.actions[1].nonceSecret, chainPortfolios[1].nonceSecret, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");

        uint256[] memory collateralTokenPrices = new uint256[](1);
        collateralTokenPrices[0] = USDC_PRICE;

        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.BorrowActionContext({
                    amount: 1e18,
                    assetSymbol: "WETH",
                    chainId: 8453,
                    collateralAmounts: collateralAmounts,
                    collateralTokenPrices: collateralTokenPrices,
                    collateralTokens: collateralTokens,
                    collateralAssetSymbols: collateralAssetSymbols,
                    comet: cometUsdc_(1),
                    price: WETH_PRICE,
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
