// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

import {Arrays} from "test/builder/lib/Arrays.sol";
import {Accounts, PaymentInfo, QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";
import {MorphoVaultActionsBuilder} from "src/builder/actions/MorphoVaultActionsBuilder.sol";
import {Actions} from "src/builder/actions/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {CometWithdrawActions, TransferActions} from "src/DeFiScripts.sol";
import {MorphoInfo} from "src/builder/MorphoInfo.sol";
import {MorphoVaultActions} from "src/MorphoScripts.sol";
import {Paycall} from "src/Paycall.sol";
import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

contract QuarkBuilderMorphoVaultWithdrawTest is Test, QuarkBuilderTest {
    function morphoWithdrawIntent_(uint256 chainId, uint256 amount, string memory assetSymbol)
        internal
        pure
        returns (MorphoVaultActionsBuilder.MorphoVaultWithdrawIntent memory)
    {
        return morphoWithdrawIntent_({
            amount: amount,
            assetSymbol: assetSymbol,
            chainId: chainId,
            withdrawer: address(0xa11ce)
        });
    }

    function morphoWithdrawIntent_(uint256 chainId, uint256 amount, string memory assetSymbol, address withdrawer)
        internal
        pure
        returns (MorphoVaultActionsBuilder.MorphoVaultWithdrawIntent memory)
    {
        return MorphoVaultActionsBuilder.MorphoVaultWithdrawIntent({
            amount: amount,
            assetSymbol: assetSymbol,
            blockTimestamp: BLOCK_TIMESTAMP,
            chainId: chainId,
            withdrawer: withdrawer
        });
    }

    // XXX test that you have enough of the asset to withdraw

    function testMorphoVaultWithdraw() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultWithdraw(
            morphoWithdrawIntent_(1, 2e6, "USDC"),
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode),
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(MorphoVaultActions.withdraw, (MorphoInfo.getMorphoVaultAddress(1, "USDC"), 2e6)),
            "calldata is MorphoVaultActions.withdraw(MorphoInfo.getMorphoVaultAddress(1, USDC), 2e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainId 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "MORPHO_VAULT_WITHDRAW", "action type is 'MORPHO_VAULT_WITHDRAW'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoVaultWithdrawActionContext({
                    amount: 2e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(1, "USDC"),
                    price: USDC_PRICE,
                    token: USDC_1
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testMorphoVaultWithdrawWithPaycall() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultWithdraw(
            morphoWithdrawIntent_(1, 2e6, "USDC"), chainAccountsList_(3e6), paymentUsdc_(maxCosts)
        );

        address morphoVaultActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode);
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
                morphoVaultActionsAddress,
                abi.encodeWithSelector(
                    MorphoVaultActions.withdraw.selector, MorphoInfo.getMorphoVaultAddress(1, "USDC"), 2e6
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoVaultActions.withdraw(MorphoInfo.getMorphoVaultAddress(1, USDC), 0.1e6);"
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
        assertEq(result.actions[0].actionType, "MORPHO_VAULT_WITHDRAW", "action type is 'MORPHO_VAULT_WITHDRAW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoVaultWithdrawActionContext({
                    amount: 2e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(1, "USDC"),
                    price: USDC_PRICE,
                    token: USDC_1
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testMorphoVaultWithdrawPayFromWithdraw() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6}); // action costs .5 USDC
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultWithdraw(
            morphoWithdrawIntent_(1, 2e6, "USDC"), chainAccountsList_(0), paymentUsdc_(maxCosts)
        );

        address morphoVaultActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode);
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
                morphoVaultActionsAddress,
                abi.encodeWithSelector(
                    MorphoVaultActions.withdraw.selector, MorphoInfo.getMorphoVaultAddress(1, "USDC"), 2e6
                ),
                0.5e6
            ),
            "calldata is Paycall.run(MorphoVaultWithdrawActions.withdraw(MorphoInfo.getMorphoVaultAddress(1, USDC), 2e6), 0.5e6);"
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
        assertEq(result.actions[0].actionType, "MORPHO_VAULT_WITHDRAW", "action type is 'MORPHO_VAULT_WITHDRAW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment max is set to .5e6 in this test case");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoVaultWithdrawActionContext({
                    amount: 2e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(1, "USDC"),
                    price: USDC_PRICE,
                    token: USDC_1
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testMorphoVaultWithdrawNotEnoughFundsToBridge() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 1000e6}); // max cost is 1000 USDC
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.1e6});
        vm.expectRevert(abi.encodeWithSelector(Actions.NotEnoughFundsToBridge.selector, "usdc", 998e6, 997.1e6));
        builder.morphoVaultWithdraw(
            morphoWithdrawIntent_(1, 1e6, "USDC"),
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
            paymentUsdc_(maxCosts)
        );
    }

    function testMorphoVaultWithdrawWithBridge() public {
        QuarkBuilder builder = new QuarkBuilder();

        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 1e6}); // max cost on base is 1 USDC

        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](2);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkSecrets: quarkSecrets_(address(0xa11ce), ALICE_DEFAULT_SECRET),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), 3e6), // 3 USDC on mainnet
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkSecrets: quarkSecrets_(address(0xb0b), BOB_DEFAULT_SECRET),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), 0), // 0 USDC on base
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });

        QuarkBuilder.BuilderResult memory result = builder.morphoVaultWithdraw(
            morphoWithdrawIntent_({chainId: 8453, amount: 1e18, assetSymbol: "WETH", withdrawer: address(0xb0b)}),
            chainAccountsList,
            paymentUsdc_(maxCosts)
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
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                ),
                0.1e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(0xBd3fa81B58Ba92a82136038B25aDec7066af3155, 1e6, 6, 0xb0b, USDC_1)), 0.1e6);"
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
                CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode),
                abi.encodeCall(MorphoVaultActions.withdraw, (MorphoInfo.getMorphoVaultAddress(8453, "WETH"), 1e18)),
                1e6
            ),
            "calldata is Paycall.run(MorphoVaultActions.withdraw(MorphoInfo.getMorphoVaultAddress(8453, WETH), 1e18);"
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
                    assetSymbol: "USDC",
                    inputAmount: 1e6,
                    outputAmount: 1e6,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP,
                    chainId: 1,
                    destinationChainId: 8453,
                    price: USDC_PRICE,
                    recipient: address(0xb0b),
                    token: USDC_1
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        // second action
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "MORPHO_VAULT_WITHDRAW", "action type is 'MORPHO_VAULT_WITHDRAW'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 1e6, "payment should have max cost of 1e6");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.MorphoVaultWithdrawActionContext({
                    amount: 1e18,
                    assetSymbol: "WETH",
                    chainId: 8453,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(8453, "WETH"),
                    price: WETH_PRICE,
                    token: weth_(8453)
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testMorphoVaultWithdrawMax() public {
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});

        MorphoVaultPortfolio[] memory morphoVaultPortfolios = new MorphoVaultPortfolio[](1);
        morphoVaultPortfolios[0] = MorphoVaultPortfolio({
            assetSymbol: "USDC",
            balance: 5e6,
            vault: MorphoInfo.getMorphoVaultAddress(1, "USDC")
        });

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](1);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: morphoVaultPortfolios
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultWithdraw(
            morphoWithdrawIntent_(1, type(uint256).max, "USDC"),
            chainAccountsFromChainPortfolios(chainPortfolios), // user has no assets
            paymentUsdc_(maxCosts) // but will pay from withdrawn funds
        );

        address paycallAddress = paycallUsdc_(1);
        address morphoVaultActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode);

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
                morphoVaultActionsAddress,
                abi.encodeWithSelector(
                    MorphoVaultActions.withdraw.selector, MorphoInfo.getMorphoVaultAddress(1, "USDC"), type(uint256).max
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoVaultActions.redeemAll(MorphoInfo.getMorphoVaultAddress(1, USDC)), 0.1e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainId 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "MORPHO_VAULT_WITHDRAW", "action type is 'MORPHO_VAULT_WITHDRAW'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to 0.1e6");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoVaultWithdrawActionContext({
                    amount: type(uint256).max,
                    assetSymbol: "USDC",
                    chainId: 1,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(1, "USDC"),
                    price: USDC_PRICE,
                    token: USDC_1
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testMorphoVaultWithdrawMaxRevertsMaxCostTooHigh() public {
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 100e6}); // max cost is very high

        MorphoVaultPortfolio[] memory morphoVaultPortfolios = new MorphoVaultPortfolio[](1);
        morphoVaultPortfolios[0] = MorphoVaultPortfolio({
            assetSymbol: "USDC",
            balance: 5e6,
            vault: MorphoInfo.getMorphoVaultAddress(1, "USDC")
        });

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](1);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nonceSecret: ALICE_DEFAULT_SECRET,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: morphoVaultPortfolios
        });

        QuarkBuilder builder = new QuarkBuilder();

        vm.expectRevert(abi.encodeWithSelector(Actions.NotEnoughFundsToBridge.selector, "usdc", 95e6, 95e6));

        builder.morphoVaultWithdraw(
            morphoWithdrawIntent_(1, type(uint256).max, "USDC"),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsdc_(maxCosts) // user will pay for transaction with withdrawn funds, but it is not enough
        );
    }
}
