// TODO: Commenting because it is currently unused and will result in stack too deep
// // SPDX-License-Identifier: BSD-3-Clause
// pragma solidity ^0.8.23;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";

// import {Arrays} from "test/builder/lib/Arrays.sol";
// import {Accounts, PaymentInfo, QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";
// import {Actions} from "src/builder/Actions.sol";
// import {CCTPBridgeActions} from "src/BridgeScripts.sol";
// import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
// import {TransferActions} from "src/DeFiScripts.sol";
// import {MorphoInfo} from "src/builder/MorphoInfo.sol";
// import {MorphoRewardsActions} from "src/MorphoScripts.sol";
// import {List} from "src/builder/List.sol";
// import {Paycall} from "src/Paycall.sol";
// import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";

// contract QuarkBuilderMorphoClaimRewardsTest is Test, QuarkBuilderTest {
//     // Fixtures of morpho reward data to pass in
//     address[] fixtureDistributors =
//         [0x330eefa8a787552DC5cAd3C3cA644844B1E61Ddb, 0x330eefa8a787552DC5cAd3C3cA644844B1E61Ddb];
//     address[] fixtureAccounts = [address(0xa11ce), address(0xa11ce)];
//     address[] fixtureRewards = [usdc_(1), weth_(1)];
//     address[] fixtureInvalidRewards = [usdc_(1)];
//     uint256[] fixtureClaimables = [100e6, 2e18];
//     uint256[] fixtureClaimablesLessUSDC = [1e6, 2e18];
//     bytes32[][] fixtureProofs = [
//         [
//             bytes32(0xce63a4c1fabb68437d0e5edc21b732c5a215f1c5a9ed6a52902f0415e148cc0a),
//             bytes32(0x23b2ad869c44ff4946d49f0e048edd1303f0cef3679d3e21143c4cfdcde97f20),
//             bytes32(0x937a82a4d574f809052269e6d4a5613fa4ce333064d012e96e9cc3c04fee7a9c),
//             bytes32(0xf93fea78509a3b4fe28d963d965ab8819bbf6c08f5789bddde16127e98e6f696),
//             bytes32(0xbb53cefdee57ab5a04a7be61a15c1ea00beacd0a4adb132dd2e046582eafbec8),
//             bytes32(0x3dcb507af99e19c829fc2f5a8f57418258230818d4db8dc3080e5cafff5bfd3c),
//             bytes32(0xca3e0c0cc07c55a02cbc21313bbd9a4d27dae6a28580fbd7dfad74216d4edac3),
//             bytes32(0x59bdab6ff3d8cd5c682ff241da1d56e9bba6f5c0a739c28629c10ffab8bb9c95),
//             bytes32(0x56a6fd126541d4a6b4902b78125db2c92b3b9cfb3249bbe3681cc2ccf9a6aa2c),
//             bytes32(0xfcfad3b73969b50e0369e94db6fcd9301b5e776784620a09c0b52a5cf3326f2b),
//             bytes32(0x7ee3c650dc15c36a6a0284c40b61391f7ac07f57d50802d92d2ccb7a19ff9dbb)
//         ],
//         [
//             bytes32(0x7ac5a364f8e3d902a778e6f22d9800304bce9a24108a6b375e9d7afffa586648),
//             bytes32(0xd0e2f9d70a7c8ddfe74cf2e922067421f06af4c16da32c13d13e6226aff54772),
//             bytes32(0x8417ffe0c1e153c75ad3bf85f8d52b22ebc5370deda637231cb7fef3238d60b7),
//             bytes32(0x99baa8011e519a6650c7f8887edde764c9198973be390dfad9a43e8af4603326),
//             bytes32(0x7db554929334c43f06c93b0917a22765ba0b27684eb3bdbb09eefaad665cf51f),
//             bytes32(0xd35638edfe77f64712acd397cfddd12da5ba480d05d77b52fa5f9f930b8c4a11),
//             bytes32(0xee0010ba447e3edda1a034acc142e66ce5c772dc9cbbdf86044e5ee760d4159f),
//             bytes32(0xedca6a5e9ba49d334eebdc4167e1730fcce5c7e4bbc17638c1cb6b4c42e85e9b),
//             bytes32(0xfd8786de55c7c2e69c4ede4fe80b5d696875621b7aea7f29736451d3ea667427),
//             bytes32(0xff695c9c3721e77a593d67cf0cbea7d495d0120ed51e31ab1428a7251665ce37),
//             bytes32(0x487b38c91a22d77f124819ab4d40eea67b11683459c458933cae385630c90816)
//         ]
//     ];

//     function morphoClaimRewardsIntent_(
//         uint256 chainId,
//         address[] memory accounts,
//         uint256[] memory claimables,
//         address[] memory distributors,
//         address[] memory rewards,
//         bytes32[][] memory proofs
//     ) internal pure returns (QuarkBuilder.MorphoRewardsClaimIntent memory) {
//         return QuarkBuilder.MorphoRewardsClaimIntent({
//             blockTimestamp: BLOCK_TIMESTAMP,
//             claimer: address(0xa11ce),
//             chainId: chainId,
//             accounts: accounts,
//             claimables: claimables,
//             distributors: distributors,
//             rewards: rewards,
//             proofs: proofs
//         });
//     }

//     function testMorphoClaimRewards() public {
//         QuarkBuilder builder = new QuarkBuilder();
//         QuarkBuilder.BuilderResult memory result = builder.morphoClaimRewards(
//             morphoClaimRewardsIntent_(
//                 1, fixtureAccounts, fixtureClaimables, fixtureDistributors, fixtureRewards, fixtureProofs
//             ),
//             chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
//             paymentUsd_()
//         );

//         assertEq(result.paymentCurrency, "usd", "usd currency");

//         // Check the quark operations
//         assertEq(result.quarkOperations.length, 1, "one operation");
//         assertEq(
//             result.quarkOperations[0].scriptAddress,
//             CodeJarHelper.getCodeAddress(type(MorphoRewardsActions).creationCode),
//             "script address is correct given the code jar address on mainnet"
//         );
//         assertEq(
//             result.quarkOperations[0].scriptCalldata,
//             abi.encodeCall(
//                 MorphoRewardsActions.claimAll,
//                 (fixtureDistributors, fixtureAccounts, fixtureRewards, fixtureClaimables, fixtureProofs)
//             ),
//             "calldata is MorphoRewardsActions.claimAll(fixtureDistributors, fixtureAccounts, fixtureRewards, fixtureClaimables, fixtureProofs);"
//         );
//         assertEq(
//             result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
//         );
//         assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
//         assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

//         // check the actions
//         assertEq(result.actions.length, 1, "one action");
//         assertEq(result.actions[0].chainId, 1, "operation is on chainId 1");
//         assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
//         assertEq(result.actions[0].actionType, "MORPHO_CLAIM_REWARDS", "action type is 'MORPHO_CLAIM_REWARDS'");
//         assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
//         assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
//         assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
//         assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
//         assertEq(result.actions[0].totalPlays, 1, "total plays is 1");

//         string[] memory assetSymbols = new string[](2);
//         assetSymbols[0] = "USDC";
//         assetSymbols[1] = "WETH";
//         uint256[] memory prices = new uint256[](2);
//         prices[0] = USDC_PRICE;
//         prices[1] = WETH_PRICE;
//         address[] memory tokens = new address[](2);
//         tokens[0] = USDC_1;
//         tokens[1] = WETH_1;
//         assertEq(
//             result.actions[0].actionContext,
//             abi.encode(
//                 Actions.MorphoClaimRewardsActionContext({
//                     amounts: fixtureClaimables,
//                     assetSymbols: assetSymbols,
//                     chainId: 1,
//                     prices: prices,
//                     tokens: tokens
//                 })
//             ),
//             "action context encoded from WithdrawActionContext"
//         );

//         // TODO: Check the contents of the EIP712 data
//         assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
//         assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
//         assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
//     }

//     function testMorphoClaimRewardsPayWithReward() public {
//         QuarkBuilder builder = new QuarkBuilder();
//         PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
//         maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 1e6});
//         QuarkBuilder.BuilderResult memory result = builder.morphoClaimRewards(
//             morphoClaimRewardsIntent_(
//                 1, fixtureAccounts, fixtureClaimables, fixtureDistributors, fixtureRewards, fixtureProofs
//             ),
//             chainAccountsList_(0),
//             paymentUsdc_(maxCosts)
//         );

//         assertEq(result.paymentCurrency, "usdc", "usdc currency");

//         // Check the quark operations
//         assertEq(result.quarkOperations.length, 1, "one operation");
//         assertEq(
//             result.quarkOperations[0].scriptAddress,
//             paycallUsdc_(1),
//             "script address is correct given the code jar address on mainnet"
//         );
//         assertEq(
//             result.quarkOperations[0].scriptCalldata,
//             abi.encodeWithSelector(
//                 Paycall.run.selector,
//                 CodeJarHelper.getCodeAddress(type(MorphoRewardsActions).creationCode),
//                 abi.encodeCall(
//                     MorphoRewardsActions.claimAll,
//                     (fixtureDistributors, fixtureAccounts, fixtureRewards, fixtureClaimables, fixtureProofs)
//                 ),
//                 1e6
//             ),
//             "calldata is Paycall.run(MorphoRewardsActions.claimAll(fixtureDistributors, fixtureAccounts, fixtureRewards, fixtureClaimables, fixtureProofs));"
//         );
//         assertEq(
//             result.quarkOperations[0].scriptSources[1],
//             abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
//         );
//         assertEq(
//             result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
//         );
//         assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
//         assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

//         // check the actions
//         assertEq(result.actions.length, 1, "one action");
//         assertEq(result.actions[0].chainId, 1, "operation is on chainId 1");
//         assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
//         assertEq(result.actions[0].actionType, "MORPHO_CLAIM_REWARDS", "action type is 'MORPHO_CLAIM_REWARDS'");
//         assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
//         assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
//         assertEq(result.actions[0].paymentMaxCost, 1e6, "payment max is set to .1e6 in this test case");
//         assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
//         assertEq(result.actions[0].totalPlays, 1, "total plays is 1");

//         string[] memory assetSymbols = new string[](2);
//         assetSymbols[0] = "USDC";
//         assetSymbols[1] = "WETH";
//         uint256[] memory prices = new uint256[](2);
//         prices[0] = USDC_PRICE;
//         prices[1] = WETH_PRICE;
//         address[] memory tokens = new address[](2);
//         tokens[0] = USDC_1;
//         tokens[1] = WETH_1;
//         assertEq(
//             result.actions[0].actionContext,
//             abi.encode(
//                 Actions.MorphoClaimRewardsActionContext({
//                     amounts: fixtureClaimables,
//                     assetSymbols: assetSymbols,
//                     chainId: 1,
//                     prices: prices,
//                     tokens: tokens
//                 })
//             ),
//             "action context encoded from WithdrawActionContext"
//         );

//         // TODO: Check the contents of the EIP712 data
//         assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
//         assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
//         assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
//     }

//     function testMorphoClaimRewardsWithNotEnoughRewardToCoverCost() public {
//         QuarkBuilder builder = new QuarkBuilder();
//         PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
//         maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 5e6});
//         maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 5e6});
//         vm.expectRevert(abi.encodeWithSelector(Actions.NotEnoughFundsToBridge.selector, "usdc", 3e6, 3e6));
//         builder.morphoClaimRewards(
//             morphoClaimRewardsIntent_(
//                 1, fixtureAccounts, fixtureClaimablesLessUSDC, fixtureDistributors, fixtureRewards, fixtureProofs
//             ),
//             chainAccountsList_(2e6),
//             paymentUsdc_(maxCosts)
//         );
//     }

//     function testMorphoClaimRewardsInvalid() public {
//         QuarkBuilder builder = new QuarkBuilder();
//         vm.expectRevert(QuarkBuilderBase.InvalidInput.selector);
//         builder.morphoClaimRewards(
//             morphoClaimRewardsIntent_(
//                 1, fixtureAccounts, fixtureClaimables, fixtureDistributors, fixtureInvalidRewards, fixtureProofs
//             ),
//             chainAccountsList_(2e6),
//             paymentUsd_()
//         );
//     }
// }
