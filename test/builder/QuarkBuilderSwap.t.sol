// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";

import {ApproveAndSwap} from "src/DeFiScripts.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {SwapActionsBuilder} from "src/builder/actions/SwapActionsBuilder.sol";
import {Actions} from "src/builder/actions/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";
import {Paycall} from "src/Paycall.sol";
import {Quotecall} from "src/Quotecall.sol";
import {Multicall} from "src/Multicall.sol";
import {WrapperActions} from "src/WrapperScripts.sol";
import {PaycallWrapper} from "src/builder/PaycallWrapper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";

contract QuarkBuilderSwapTest is Test, QuarkBuilderTest {
    address constant ZERO_EX_ENTRY_POINT = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    bytes constant ZERO_EX_SWAP_DATA = hex"abcdef";

    function buyUsdc_(
        uint256 chainId,
        address sellToken,
        uint256 sellAmount,
        uint256 buyAmount,
        address sender,
        uint256 blockTimestamp
    ) internal pure returns (SwapActionsBuilder.ZeroExSwapIntent memory) {
        address usdc = usdc_(chainId);
        return zeroExSwap_(
            chainId,
            ZERO_EX_ENTRY_POINT,
            ZERO_EX_SWAP_DATA,
            sellToken,
            sellAmount,
            usdc,
            buyAmount,
            sender,
            blockTimestamp
        );
    }

    function buyWeth_(
        uint256 chainId,
        address sellToken,
        uint256 sellAmount,
        uint256 buyAmount,
        address sender,
        uint256 blockTimestamp
    ) internal pure returns (SwapActionsBuilder.ZeroExSwapIntent memory) {
        address weth = weth_(chainId);
        return zeroExSwap_(
            chainId,
            ZERO_EX_ENTRY_POINT,
            ZERO_EX_SWAP_DATA,
            sellToken,
            sellAmount,
            weth,
            buyAmount,
            sender,
            blockTimestamp
        );
    }

    function zeroExSwap_(
        uint256 chainId,
        address entryPoint,
        bytes memory swapData,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount,
        address sender,
        uint256 blockTimestamp
    ) internal pure returns (SwapActionsBuilder.ZeroExSwapIntent memory) {
        return SwapActionsBuilder.ZeroExSwapIntent({
            chainId: chainId,
            entryPoint: entryPoint,
            swapData: swapData,
            sellToken: sellToken,
            sellAmount: sellAmount,
            buyToken: buyToken,
            buyAmount: buyAmount,
            feeToken: buyToken,
            feeAmount: 10,
            sender: sender,
            isExactOut: false,
            blockTimestamp: blockTimestamp,
            preferAcross: false
        });
    }

    function testInsufficientFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "USDC", 3000e6, 0e6));
        builder.swap(
            buyWeth_(1, usdc_(1), 3000e6, 1e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 1 to 1 WETH
            chainAccountsList_(0e6), // but we are holding 0 USDC in total across 1, 8453
            paymentUsd_()
        );
    }

    // TODO: This no longer tests for the MaxCostTooHigh, since it may be unreachable now. Verify that this is the case.
    function testMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        // Max cost is too high, so total available funds is 0
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "USDC", 30e6, 0e6));
        builder.swap(
            buyWeth_(1, usdc_(1), 30e6, 0.01e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 30 USDC on chain 1 to 0.01 WETH
            chainAccountsList_(60e6), // holding 60 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts_(1, 1_000e6)) // but costs 1,000 USDC
        );
    }

    function testFundsOnUnbridgeableChains() public {
        QuarkBuilder builder = new QuarkBuilder();
        // FundsUnavailable("USDC", 2e6, 0e6): Requested 2e6, Available 0e6
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "USDC", 30e6, 0e6));
        builder.swap(
            // there is no bridge to chain 7777, so we cannot get to our funds
            buyWeth_(7777, usdc_(7777), 30e6, 0.01e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 30 USDC on chain 1 to 0.01 WETH
            chainAccountsList_(60e6), // holding 60 USDC in total across chains 1, 8453
            paymentUsd_()
        );
    }

    function testFundsUnavailableErrorGivesSuggestionForAvailableFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        // The 32e6 is the suggested amount (total available funds) to swap
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "USDC", 30e6, 27e6));
        builder.swap(
            buyWeth_(1, usdc_(1), 30e6, 0.01e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap 30 USDC on chain 1 to 0.01 WETH
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
            abi.encodeCall(ApproveAndSwap.run, (ZERO_EX_ENTRY_POINT, USDC_1, 3000e6, WETH_1, 1e18, ZERO_EX_SWAP_DATA)),
            "calldata is ApproveAndSwap.run(ZERO_EX_ENTRY_POINT, USDC_1, 3500e6, WETH_1, 1e18, ZERO_EX_SWAP_DATA);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce does the swap");
        assertEq(result.actions[0].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 1,
                    feeAmount: 10,
                    feeAssetSymbol: "WETH",
                    feeToken: WETH_1,
                    feeTokenPrice: WETH_PRICE,
                    inputToken: USDC_1,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_1,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18,
                    isExactOut: false
                })
            ),
            "action context encoded from SwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testLocalSwapWithAutoWrapperSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        address account = address(0xa11ce);
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](1);
        // Custom setup to hold just ETH (for auto wrap later)
        Accounts.AssetPositions[] memory assetPositionsList = new Accounts.AssetPositions[](3);
        assetPositionsList[0] = Accounts.AssetPositions({
            asset: eth_(),
            symbol: "ETH",
            decimals: 18,
            usdPrice: WETH_PRICE,
            accountBalances: accountBalances_(account, 1e18)
        });
        assetPositionsList[1] = Accounts.AssetPositions({
            asset: weth_(1),
            symbol: "WETH",
            decimals: 18,
            usdPrice: WETH_PRICE,
            accountBalances: accountBalances_(account, 0)
        });
        assetPositionsList[2] = Accounts.AssetPositions({
            asset: usdc_(1),
            symbol: "USDC",
            decimals: 6,
            usdPrice: USDC_PRICE,
            accountBalances: accountBalances_(account, 10e6)
        });
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkSecrets: quarkSecrets_(address(0xa11ce), bytes32(uint256(12))),
            assetPositionsList: assetPositionsList,
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });
        QuarkBuilder.BuilderResult memory result = builder.swap(
            buyUsdc_(1, weth_(1), 1e18, 3000e6, address(0xa11ce), BLOCK_TIMESTAMP), // swap 1 ETH on chain 1 to 3000 USDC
            chainAccountsList, // holding 1ETH in total in chains 1
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        address multicallAddress = CodeJarHelper.getCodeAddress(type(Multicall).creationCode);
        address wrapperActionsAddress = CodeJarHelper.getCodeAddress(type(WrapperActions).creationCode);
        address approveAndSwapAddress = CodeJarHelper.getCodeAddress(type(ApproveAndSwap).creationCode);
        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one merged operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            multicallAddress,
            "script address is correct given the code jar address on mainnet"
        );
        address[] memory callContracts = new address[](2);
        callContracts[0] = wrapperActionsAddress;
        callContracts[1] = approveAndSwapAddress;
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] =
            abi.encodeWithSelector(WrapperActions.wrapAllETH.selector, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        callDatas[1] =
            abi.encodeCall(ApproveAndSwap.run, (ZERO_EX_ENTRY_POINT, WETH_1, 1e18, USDC_1, 3000e6, ZERO_EX_SWAP_DATA));
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
            "calldata is Multicall.run([wrapperActionsAddress, approveAndSwapAddress], [WrapperActions.wrapAllETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), ApproveAndSwap.run (ZERO_EX_ENTRY_POINT, WETH_1, 1e18, USDC_1, 3000e6,  ZERO_EX_SWAP_DATA)]);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce does the swap");
        assertEq(result.actions[0].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 1,
                    feeAmount: 10,
                    feeAssetSymbol: "USDC",
                    feeToken: USDC_1,
                    feeTokenPrice: USDC_PRICE,
                    inputToken: WETH_1,
                    inputTokenPrice: WETH_PRICE,
                    inputAssetSymbol: "WETH",
                    inputAmount: 1e18,
                    outputToken: USDC_1,
                    outputTokenPrice: USDC_PRICE,
                    outputAssetSymbol: "USDC",
                    outputAmount: 3000e6,
                    isExactOut: false
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
                    ApproveAndSwap.run.selector, ZERO_EX_ENTRY_POINT, USDC_1, 3000e6, WETH_1, 1e18, ZERO_EX_SWAP_DATA
                ),
                5e6
            ),
            "calldata is Paycall.run(ApproveAndSwap.run(ZERO_EX_ENTRY_POINT, USDC_1, 3500e6, WETH_1, 1e18, ZERO_EX_SWAP_DATA), 5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce does the swap");
        assertEq(result.actions[0].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment max is set to 5e6 in this test case");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 1,
                    feeAmount: 10,
                    feeAssetSymbol: "WETH",
                    feeToken: WETH_1,
                    feeTokenPrice: WETH_PRICE,
                    inputToken: USDC_1,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_1,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18,
                    isExactOut: false
                })
            ),
            "action context encoded from SwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testSwapMaxSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 5e6});
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](3);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkSecrets: quarkSecrets_(address(0xa11ce), bytes32(uint256(12))),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), uint256(9005e6)),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkSecrets: quarkSecrets_(address(0xb0b), bytes32(uint256(2))),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), uint256(0)),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });
        chainAccountsList[2] = Accounts.ChainAccounts({
            chainId: 7777,
            quarkSecrets: quarkSecrets_(address(0xc0b), bytes32(uint256(5))),
            assetPositionsList: assetPositionsList_(7777, address(0xc0b), uint256(0)),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });

        QuarkBuilder.BuilderResult memory result = builder.swap(
            buyWeth_(1, usdc_(1), type(uint256).max, 3e18, address(0xa11ce), BLOCK_TIMESTAMP), // swap max on chain 1
            chainAccountsList, // holding 9005 USDC in total chains 1
            paymentUsdc_(maxCosts)
        );

        address approveAndSwapAddress = CodeJarHelper.getCodeAddress(type(ApproveAndSwap).creationCode);
        address quotecallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            quotecallAddress,
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                approveAndSwapAddress,
                abi.encodeWithSelector(
                    ApproveAndSwap.run.selector, ZERO_EX_ENTRY_POINT, USDC_1, 9000e6, WETH_1, 3e18, ZERO_EX_SWAP_DATA
                ),
                5e6
            ),
            "calldata is Quotecall.run(ApproveAndSwap.run(ZERO_EX_ENTRY_POINT, USDC_1, 9000e6, WETH_1, 3e18, ZERO_EX_SWAP_DATA), 5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce does the swap");
        assertEq(result.actions[0].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[0].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment max is set to 5e6 in this test case");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 1,
                    feeAmount: 10,
                    feeAssetSymbol: "WETH",
                    feeToken: WETH_1,
                    feeTokenPrice: WETH_PRICE,
                    inputToken: USDC_1,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 9000e6,
                    outputToken: WETH_1,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 3e18,
                    isExactOut: false
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
            buyWeth_(8453, usdc_(8453), 3000e6, 1e18, address(0xb0b), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 8453 to 1 WETH
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
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                )
            ),
            "calldata is CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 2e6, 6, bytes32(uint256(uint160(0xb0b))), usdc_(1)));"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

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
            "script address for swap is correct given the code jar address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeCall(
                ApproveAndSwap.run, (ZERO_EX_ENTRY_POINT, USDC_8453, 3000e6, WETH_8453, 1e18, ZERO_EX_SWAP_DATA)
            ),
            "calldata is ApproveAndSwap.run(ZERO_EX_ENTRY_POINT, USDC_8453, 3500e6, WETH_8453, 1e18, ZERO_EX_SWAP_DATA);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[1].nonce, BOB_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[1].isReplayable, false, "isReplayable is false");

        // Check the actions
        assertEq(result.actions.length, 2, "two actions");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    price: USDC_PRICE,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    inputAmount: 1000e6,
                    outputAmount: 1000e6,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[1].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[1].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[1].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 8453,
                    feeAmount: 10,
                    feeAssetSymbol: "WETH",
                    feeToken: WETH_8453,
                    feeTokenPrice: WETH_PRICE,
                    inputToken: USDC_8453,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_8453,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18,
                    isExactOut: false
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
            buyWeth_(8453, usdc_(8453), 3000e6, 1e18, address(0xb0b), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 8453 to 1 WETH
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
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                ),
                5e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 2.1e6, 6, bytes32(uint256(uint160(0xb0b))), usdc_(1))), 5e5);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

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
                    ZERO_EX_ENTRY_POINT,
                    USDC_8453,
                    3000e6,
                    WETH_8453,
                    1e18,
                    ZERO_EX_SWAP_DATA
                ),
                1e6
            ),
            "calldata is Paycall.run(ApproveAndSwap.run(ZERO_EX_ENTRY_POINT, USDC_8453, 3500e6, WETH_8453, 1e18, ZERO_EX_SWAP_DATA), 5e6);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[1].nonce, BOB_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[1].isReplayable, false, "isReplayable is false");

        // Check the actions
        assertEq(result.actions.length, 2, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment should have max cost of 5e6");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    price: USDC_PRICE,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    inputAmount: 1001e6,
                    outputAmount: 1001e6,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 1e6, "payment should have max cost of 1e6");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 8453,
                    feeAmount: 10,
                    feeAssetSymbol: "WETH",
                    feeToken: WETH_8453,
                    feeTokenPrice: WETH_PRICE,
                    inputToken: USDC_8453,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputToken: WETH_8453,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18,
                    isExactOut: false
                })
            ),
            "action context encoded from SwapActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testBridgeSwapMaxWithQuotecallSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 5e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e6});
        QuarkBuilder.BuilderResult memory result = builder.swap(
            buyWeth_(8453, usdc_(8453), type(uint256).max, 2e18, address(0xb0b), BLOCK_TIMESTAMP), // swap max on chain 8453 to 4 WETH
            chainAccountsList_(6010e6), // holding 6010 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address approveAndSwapAddress = CodeJarHelper.getCodeAddress(type(ApproveAndSwap).creationCode);
        address quotecallAddress = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
        );
        address quotecallAddressBase = CodeJarHelper.getCodeAddress(
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
        );
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);

        assertEq(result.paymentCurrency, "usdc", "usdc currency");

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
                    3000e6,
                    6,
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                ),
                5e6
            ),
            "calldata is Quotecall.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 3000e6, 6, bytes32(uint256(uint160(0xb0b))), usdc_(1))), 5e5);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        assertEq(
            result.quarkOperations[1].scriptAddress,
            quotecallAddressBase,
            "script address[1] has been wrapped with quotecall address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                approveAndSwapAddress,
                abi.encodeWithSelector(
                    ApproveAndSwap.run.selector,
                    ZERO_EX_ENTRY_POINT,
                    USDC_8453,
                    6004e6,
                    WETH_8453,
                    2e18,
                    ZERO_EX_SWAP_DATA
                ),
                1e6
            ),
            "calldata is Quotecall.run(ApproveAndSwap.run(ZERO_EX_ENTRY_POINT, USDC_8453, 3500e6, WETH_8453, 1e18, ZERO_EX_SWAP_DATA), 5e6);"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[1].nonce, BOB_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[1].isReplayable, false, "isReplayable is false");

        // Check the actions
        assertEq(result.actions.length, 2, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment should have max cost of 5e6");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    price: USDC_PRICE,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    inputAmount: 3000e6,
                    outputAmount: 3000e6,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[1].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 1e6, "payment should have max cost of 1e6");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 8453,
                    feeAmount: 10,
                    feeAssetSymbol: "WETH",
                    feeToken: WETH_8453,
                    feeTokenPrice: WETH_PRICE,
                    inputToken: USDC_8453,
                    inputTokenPrice: USDC_PRICE,
                    inputAssetSymbol: "USDC",
                    inputAmount: 6004e6,
                    outputToken: WETH_8453,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 2e18,
                    isExactOut: false
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
            buyWeth_(8453, usdt_(8453), 3000e6, 1e18, address(0xb0b), BLOCK_TIMESTAMP), // swap 3000 USDT on chain 8453 to 1 WETH
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
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                ),
                5e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 500e6, 6, bytes32(uint256(uint160(0xb0b))), usdc_(1))), 5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Paycall.run.selector,
                approveAndSwapAddress,
                abi.encodeWithSelector(
                    ApproveAndSwap.run.selector,
                    ZERO_EX_ENTRY_POINT,
                    USDT_8453,
                    3000e6,
                    WETH_8453,
                    1e18,
                    ZERO_EX_SWAP_DATA
                ),
                3500e6
            ),
            "calldata is Paycall.run(ApproveAndSwap.run(ZERO_EX_ENTRY_POINT, USDT_8453, 3500e6, WETH_8453, 1e18, ZERO_EX_SWAP_DATA), 3500e6);"
        );
        assertEq(
            result.quarkOperations[1].scriptAddress,
            paycallAddressBase,
            "script address[1] has been wrapped with paycall address"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 3 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[1].nonce, BOB_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[1].isReplayable, false, "isReplayable is false");

        // Check the actions
        assertEq(result.actions.length, 2, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "BRIDGE", "action type is 'BRIDGE'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 5e6, "payment should have max cost of 5e6");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    price: USDC_PRICE,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    inputAmount: 500e6,
                    outputAmount: 500e6,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "SWAP", "action type is 'SWAP'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 3500e6, "payment should have max cost of 3500e6");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.SwapActionContext({
                    chainId: 8453,
                    feeAmount: 10,
                    feeAssetSymbol: "WETH",
                    feeToken: WETH_8453,
                    feeTokenPrice: WETH_PRICE,
                    inputToken: USDT_8453,
                    inputTokenPrice: USDT_PRICE,
                    inputAssetSymbol: "USDT",
                    inputAmount: 3000e6,
                    outputToken: WETH_8453,
                    outputTokenPrice: WETH_PRICE,
                    outputAssetSymbol: "WETH",
                    outputAmount: 1e18,
                    isExactOut: false
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
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "USDC", 3000e6, 1999e6));
        builder.swap(
            buyWeth_(8453, usdc_(8453), 3000e6, 1e18, address(0xc0b), BLOCK_TIMESTAMP), // swap 3000 USDC on chain 8453 to 1 WETH
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
