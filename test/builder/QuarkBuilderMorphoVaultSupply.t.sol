// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilderTest, Accounts, PaymentInfo} from "test/builder/lib/QuarkBuilderTest.sol";
import {MorphoVaultActionsBuilder} from "src/builder/actions/MorphoVaultActionsBuilder.sol";
import {Actions} from "src/builder/actions/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {CometSupplyActions, TransferActions} from "src/DeFiScripts.sol";
import {Paycall} from "src/Paycall.sol";
import {MorphoInfo} from "src/builder/MorphoInfo.sol";
import {MorphoVaultActions} from "src/MorphoScripts.sol";
import {Multicall} from "src/Multicall.sol";
import {Quotecall} from "src/Quotecall.sol";
import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";
import {WrapperActions} from "src/WrapperScripts.sol";

contract QuarkBuilderMorphoVaultTest is Test, QuarkBuilderTest {
    function morphoSupplyIntent_(uint256 chainId, uint256 amount, string memory assetSymbol)
        internal
        pure
        returns (MorphoVaultActionsBuilder.MorphoVaultSupplyIntent memory)
    {
        return
            morphoSupplyIntent_({chainId: chainId, amount: amount, assetSymbol: assetSymbol, sender: address(0xa11ce)});
    }

    function morphoSupplyIntent_(uint256 chainId, uint256 amount, string memory assetSymbol, address sender)
        internal
        pure
        returns (MorphoVaultActionsBuilder.MorphoVaultSupplyIntent memory)
    {
        return MorphoVaultActionsBuilder.MorphoVaultSupplyIntent({
            amount: amount,
            assetSymbol: assetSymbol,
            blockTimestamp: BLOCK_TIMESTAMP,
            chainId: chainId,
            sender: sender,
            preferAcross: false
        });
    }

    function testInsufficientFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "USDC", 2e6, 0e6));
        builder.morphoVaultSupply(
            MorphoVaultActionsBuilder.MorphoVaultSupplyIntent({
                amount: 2e6,
                assetSymbol: "USDC",
                blockTimestamp: BLOCK_TIMESTAMP,
                sender: address(0xa11ce),
                chainId: 1,
                preferAcross: false
            }),
            chainAccountsList_(0e6), // but we are holding 0 USDC in total across 1, 8453
            paymentUsd_()
        );
    }

    function testMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        // Max cost is too high, so total available funds is 0
        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "USDC", 1e6, 0e6));
        builder.morphoVaultSupply(
            MorphoVaultActionsBuilder.MorphoVaultSupplyIntent({
                amount: 1e6,
                assetSymbol: "USDC",
                blockTimestamp: BLOCK_TIMESTAMP,
                sender: address(0xa11ce),
                chainId: 1,
                preferAcross: false
            }),
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
            paymentUsdc_(maxCosts_(1, 1_000e6)) // but costs 1,000 USDC
        );
    }

    function testFundsUnavailable() public {
        QuarkBuilder builder = new QuarkBuilder();
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](3);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkSecrets: quarkSecrets_(address(0xa11ce), bytes32(uint256(12))),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), 0e6),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkSecrets: quarkSecrets_(address(0xb0b), bytes32(uint256(2))),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), 0e6),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });
        chainAccountsList[2] = Accounts.ChainAccounts({
            chainId: 7777,
            quarkSecrets: quarkSecrets_(address(0xc0b), bytes32(uint256(5))),
            assetPositionsList: assetPositionsList_(7777, address(0xc0b), 100e6),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });

        vm.expectRevert(abi.encodeWithSelector(QuarkBuilderBase.FundsUnavailable.selector, "USDC", 2e6, 0));
        builder.morphoVaultSupply(
            // there is no bridge to brige from 7777, so we cannot get to our funds
            MorphoVaultActionsBuilder.MorphoVaultSupplyIntent({
                amount: 2e6,
                assetSymbol: "USDC",
                blockTimestamp: BLOCK_TIMESTAMP,
                sender: address(0xa11ce),
                chainId: 1,
                preferAcross: false
            }),
            chainAccountsList,
            paymentUsd_()
        );
    }

    function testSimpleMorphoVaultSupply() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultSupply(
            MorphoVaultActionsBuilder.MorphoVaultSupplyIntent({
                amount: 1e6,
                assetSymbol: "USDC",
                blockTimestamp: BLOCK_TIMESTAMP,
                sender: address(0xa11ce),
                chainId: 1,
                preferAcross: false
            }),
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
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
            abi.encodeCall(MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(1, "USDC"), usdc_(1), 1e6)),
            "calldata is MorphoVaultActions.deposit(MorphoInfo.getMorphoVaultAddress(1, USDC), usdc_(1), 1e6);"
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
        assertEq(result.actions[0].actionType, "MORPHO_VAULT_SUPPLY", "action type is 'MORPHO_VAULT_SUPPLY'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoVaultSupplyActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(1, "USDC"),
                    price: USDC_PRICE,
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

    function testSimpleMorphoVaultSupplyMax() public {
        QuarkBuilder builder = new QuarkBuilder();
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](1);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkSecrets: quarkSecrets_(address(0xa11ce), bytes32(uint256(12))),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), uint256(3e6)),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });

        QuarkBuilder.BuilderResult memory result = builder.morphoVaultSupply(
            MorphoVaultActionsBuilder.MorphoVaultSupplyIntent({
                amount: type(uint256).max,
                assetSymbol: "USDC",
                blockTimestamp: BLOCK_TIMESTAMP,
                sender: address(0xa11ce),
                chainId: 1,
                preferAcross: false
            }),
            chainAccountsList, // holding 3 USDC in total across chains 1, 8453
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
            abi.encodeCall(MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(1, "USDC"), usdc_(1), 3e6)),
            "calldata is MorphoVaultActions.deposit(MorphoInfo.getMorphoVaultAddress(1, USDC), usdc_(1), 3e6);"
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
        assertEq(result.actions[0].actionType, "MORPHO_VAULT_SUPPLY", "action type is 'MORPHO_VAULT_SUPPLY'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoVaultSupplyActionContext({
                    amount: 3e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(1, "USDC"),
                    price: USDC_PRICE,
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

    function testSimpleMorphoVaultSupplyWithAutoWrapper() public {
        QuarkBuilder builder = new QuarkBuilder();
        address account = address(0xa11ce);
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](1);
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
            accountBalances: accountBalances_(account, 0e6)
        });
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkSecrets: quarkSecrets_(address(0xa11ce), bytes32(uint256(12))),
            assetPositionsList: assetPositionsList,
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });

        QuarkBuilder.BuilderResult memory result =
            builder.morphoVaultSupply(morphoSupplyIntent_(1, 1e18, "WETH"), chainAccountsList, paymentUsd_());

        assertEq(result.paymentCurrency, "usd", "usd currency");

        address multicallAddress = CodeJarHelper.getCodeAddress(type(Multicall).creationCode);
        address wrapperActionsAddress = CodeJarHelper.getCodeAddress(type(WrapperActions).creationCode);
        address morphoVaultActionsAddress = CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode);
        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one merged operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            multicallAddress,
            "script address is correct given the code jar address on mainnet"
        );
        address[] memory callContracts = new address[](2);
        callContracts[0] = wrapperActionsAddress;
        callContracts[1] = morphoVaultActionsAddress;
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] =
            abi.encodeWithSelector(WrapperActions.wrapAllETH.selector, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        callDatas[1] =
            abi.encodeCall(MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(1, "WETH"), weth_(1), 1e18));
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
            "calldata is Multicall.run([wrapperActionsAddress, morphoVaultActionsAddress], [WrapperActions.wrapAllETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), MorphoVaultActions.deposit(MorphoInfo.getMorphoVaultAddress(1, WETH), weth_(1), 1e18)"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 3 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // check the actions
        assertEq(result.actions.length, 1, "one action");
        assertEq(result.actions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.actions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.actions[0].actionType, "MORPHO_VAULT_SUPPLY", "action type is 'MORPHO_VAULT_SUPPLY'");
        assertEq(result.actions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoVaultSupplyActionContext({
                    amount: 1e18,
                    assetSymbol: "WETH",
                    chainId: 1,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(1, "WETH"),
                    price: WETH_PRICE,
                    token: WETH_1
                })
            ),
            "action context encoded from SupplyActionContext"
        );

        // // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    function testMorphoVaultSupplyWithPaycall() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.1e6});
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultSupply(
            morphoSupplyIntent_(1, 1e6, "USDC"),
            chainAccountsList_(3e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
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
                    MorphoVaultActions.deposit.selector, MorphoInfo.getMorphoVaultAddress(1, "USDC"), usdc_(1), 1e6
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoVaultActions.deposit(MorphoInfo.getMorphoVaultAddress(1, USDC), usdc_(1), 1e6), 0.1e6);"
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
        assertEq(result.actions[0].actionType, "MORPHO_VAULT_SUPPLY", "action type is 'MORPHO_VAULT_SUPPLY'");
        assertEq(result.actions[0].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC");
        assertEq(result.actions[0].paymentMaxCost, 0.1e6, "payment max is set to .1e6 in this test case");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.MorphoVaultSupplyActionContext({
                    amount: 1e6,
                    assetSymbol: "USDC",
                    chainId: 1,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(1, "USDC"),
                    price: USDC_PRICE,
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

    function testMorphoVaultSupplyWithBridge() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultSupply(
            morphoSupplyIntent_(8453, 5e6, "USDC", address(0xb0b)),
            chainAccountsList_(6e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        // Check the quark operations
        // first operation
        assertEq(result.quarkOperations.length, 2, "two operations");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode),
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

        // second operation
        assertEq(
            result.quarkOperations[1].scriptAddress,
            CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode),
            "script address for transfer is correct given the code jar address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeCall(
                MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(8453, "USDC"), usdc_(8453), 5e6)
            ),
            "calldata is MorphoVaultActions.deposit(MorphoInfo.getMorphoVaultAddress(8453, USDC), usdc_(8453), 5e6)"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[1].nonce, BOB_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[1].isReplayable, false, "isReplayable is false");

        // check the actions
        // first action
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
                    inputAmount: 2e6,
                    outputAmount: 2e6,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );

        // second action
        assertEq(result.actions[1].chainId, 8453, "second action is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "MORPHO_VAULT_SUPPLY", "action type is 'MORPHO_VAULT_SUPPLY'");
        assertEq(result.actions[1].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[1].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[1].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.MorphoVaultSupplyActionContext({
                    amount: 5e6,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(8453, "USDC"),
                    price: USDC_PRICE,
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

    function testMorphoVaultSupplyMaxWithBridge() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultSupply(
            morphoSupplyIntent_(8453, type(uint256).max, "USDC", address(0xb0b)),
            chainAccountsList_(6e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        // Check the quark operations
        // first operation
        assertEq(result.quarkOperations.length, 2, "two operations");
        assertEq(
            result.quarkOperations[0].scriptAddress,
            CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode),
            "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(
                CCTPBridgeActions.bridgeUSDC,
                (
                    address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155),
                    3e6,
                    6,
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                )
            ),
            "calldata is CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 3e6, 6, bytes32(uint256(uint160(0xb0b))), usdc_(1)));"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // second operation
        assertEq(
            result.quarkOperations[1].scriptAddress,
            CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode),
            "script address for transfer is correct given the code jar address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeCall(
                MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(8453, "USDC"), usdc_(8453), 6e6)
            ),
            "calldata is MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(8453, USDC), usdc_(8453), 6e6)"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[1].nonce, BOB_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[1].isReplayable, false, "isReplayable is false");

        // check the actions
        // first action
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
                    inputAmount: 3e6,
                    outputAmount: 3e6,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_CCTP
                })
            ),
            "action context encoded from BridgeActionContext"
        );

        // second action
        assertEq(result.actions[1].chainId, 8453, "second action is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "MORPHO_VAULT_SUPPLY", "action type is 'MORPHO_VAULT_SUPPLY'");
        assertEq(result.actions[1].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[1].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[1].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.MorphoVaultSupplyActionContext({
                    amount: 6e6,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(8453, "USDC"),
                    price: USDC_PRICE,
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

    function testMorphoVaultSupplyMaxWithBridgeAndQuotecall() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.1e6});

        // Note: There are 3e6 USDC on each chain, so the Builder should attempt to bridge 2 USDC to chain 8453
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultSupply(
            morphoSupplyIntent_(8453, type(uint256).max, "USDC", address(0xb0b)),
            chainAccountsList_(6e6), // holding 3 USDC in total across chains 1, 8453
            paymentUsdc_(maxCosts)
        );

        address quotecallAddress = quotecallUsdc_(1);
        address quotecallAddressBase = quotecallUsdc_(8453);
        address cctpBridgeActionsAddress = CodeJarHelper.getCodeAddress(type(CCTPBridgeActions).creationCode);

        assertEq(result.paymentCurrency, "usdc", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 2, "two operations");
        // first operation
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
                    2.5e6, // 3e6 - 0.5e6
                    6,
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                ),
                0.5e6
            ),
            "calldata is Quotecall.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 2.1e6, 6, bytes32(uint256(uint160(0xb0b))), usdc_(1))), 0.5e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        // second operation
        assertEq(
            result.quarkOperations[1].scriptAddress,
            quotecallAddressBase,
            "script address[1] has been wrapped with quotecall address"
        );
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                CodeJarHelper.getCodeAddress(type(MorphoVaultActions).creationCode),
                abi.encodeCall(
                    MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(8453, "USDC"), usdc_(8453), 5.4e6)
                ),
                0.1e6
            ),
            "calldata is Quotecall.run(MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(8453, USDC), usdc_(8453), 5.4e6)), 0.1e6);"
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
        assertEq(result.actions[0].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[0].paymentToken, USDC_1, "payment token is USDC on mainnet");
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment should have max cost of 0.5e6");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    price: USDC_PRICE,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    inputAmount: 2.5e6,
                    outputAmount: 2.5e6,
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
        assertEq(result.actions[1].actionType, "MORPHO_VAULT_SUPPLY", "action type is 'MORPHO_VAULT_SUPPLY'");
        assertEq(result.actions[1].paymentMethod, "QUOTE_CALL", "payment method is 'QUOTE_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 0.1e6, "payment should have max cost of 0.1e6");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.MorphoVaultSupplyActionContext({
                    amount: 5.4e6,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(8453, "USDC"),
                    price: USDC_PRICE,
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

    function testMorphoVaultSupplyWithBridgeAndPaycall() public {
        QuarkBuilder builder = new QuarkBuilder();
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](2);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: 1, amount: 0.5e6});
        maxCosts[1] = PaymentInfo.PaymentMaxCost({chainId: 8453, amount: 0.1e6});

        // Note: There are 3e6 USDC on each chain, so the Builder should attempt to bridge 2 USDC to chain 8453
        QuarkBuilder.BuilderResult memory result = builder.morphoVaultSupply(
            morphoSupplyIntent_(8453, 5e6, "USDC", address(0xb0b)),
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
                    bytes32(uint256(uint160(0xb0b))),
                    usdc_(1)
                ),
                0.5e6
            ),
            "calldata is Paycall.run(CCTPBridgeActions.bridgeUSDC(address(0xBd3fa81B58Ba92a82136038B25aDec7066af3155), 2.1e6, 6, bytes32(uint256(uint160(0xb0b))), usdc_(1))), 0.5e6);"
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
                abi.encodeCall(
                    MorphoVaultActions.deposit, (MorphoInfo.getMorphoVaultAddress(8453, "USDC"), usdc_(8453), 5e6)
                ),
                0.1e6
            ),
            "calldata is Paycall.run(MorphoInfo.getMorphoVaultAddress(8453, USDC), usdc_(8453), 5e6), 0.1e6);"
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
        assertEq(result.actions[0].paymentMaxCost, 0.5e6, "payment should have max cost of 0.5e6");
        assertEq(result.actions[0].nonceSecret, ALICE_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[0].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[0].actionContext,
            abi.encode(
                Actions.BridgeActionContext({
                    price: USDC_PRICE,
                    token: USDC_1,
                    assetSymbol: "USDC",
                    inputAmount: 2.1e6,
                    outputAmount: 2.1e6,
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
        assertEq(result.actions[1].actionType, "MORPHO_VAULT_SUPPLY", "action type is 'MORPHO_VAULT_SUPPLY'");
        assertEq(result.actions[1].paymentMethod, "PAY_CALL", "payment method is 'PAY_CALL'");
        assertEq(result.actions[1].paymentToken, USDC_8453, "payment token is USDC on Base");
        assertEq(result.actions[1].paymentMaxCost, 0.1e6, "payment should have max cost of 0.1e6");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.MorphoVaultSupplyActionContext({
                    amount: 5e6,
                    assetSymbol: "USDC",
                    chainId: 8453,
                    morphoVault: MorphoInfo.getMorphoVaultAddress(8453, "USDC"),
                    price: USDC_PRICE,
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
