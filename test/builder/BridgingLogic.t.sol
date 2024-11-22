// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";

import {AcrossActions} from "src/AcrossScripts.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {Multicall} from "src/Multicall.sol";
import {TransferActions} from "src/DeFiScripts.sol";
import {WrapperActions} from "src/WrapperScripts.sol";
import {TransferActionsBuilder} from "src/builder/actions/TransferActionsBuilder.sol";
import {Actions} from "src/builder/actions/Actions.sol";
import {Accounts} from "src/builder/Accounts.sol";
import {Across} from "src/builder/BridgeRoutes.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {FFI} from "src/builder/FFI.sol";
import {Paycall} from "src/Paycall.sol";
import {PaycallWrapper} from "src/builder/PaycallWrapper.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";
import {Quotecall} from "src/Quotecall.sol";
import {TokenWrapper} from "src/builder/TokenWrapper.sol";
import {YulHelper} from "test/lib/YulHelper.sol";

import {MockAcrossFFI, MockAcrossFFIConstants} from "test/builder/mocks/AcrossFFI.sol";

contract BridgingLogicTest is Test, QuarkBuilderTest {
    function setUp() public {
        // Deploy mock FFI for calling Across API
        MockAcrossFFI mockFFI = new MockAcrossFFI();
        vm.etch(FFI.ACROSS_FFI_ADDRESS, address(mockFFI).code);
    }

    function testSimpleBridgeWETHTransferSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](2);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkSecrets: quarkSecrets_(address(0xa11ce), bytes32(uint256(12))),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), 1e18),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkSecrets: quarkSecrets_(address(0xb0b), bytes32(uint256(2))),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), 0.5e18),
            cometPositions: emptyCometPositions_(),
            morphoPositions: emptyMorphoPositions_(),
            morphoVaultPositions: emptyMorphoVaultPositions_()
        });

        QuarkBuilder.BuilderResult memory result = builder.transfer(
            TransferActionsBuilder.TransferIntent({
                assetSymbol: "WETH",
                chainId: 8453,
                amount: 1e18,
                sender: address(0xb0b),
                recipient: address(0xceecee),
                blockTimestamp: BLOCK_TIMESTAMP,
                preferAcross: false
            }), // transfer 1e18 WETH on chain 8453 to 0xceecee
            chainAccountsList,
            paymentUsd_()
        );

        assertEq(result.paymentCurrency, "usd", "usd currency");

        address multicallAddress = CodeJarHelper.getCodeAddress(type(Multicall).creationCode);
        address wrapperActionsAddress = CodeJarHelper.getCodeAddress(type(WrapperActions).creationCode);
        address transferActionsAddress = CodeJarHelper.getCodeAddress(type(TransferActions).creationCode);

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
                                keccak256(type(AcrossActions).creationCode)
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
                AcrossActions.depositV3,
                (
                    address(0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5), // spokePool
                    address(0xb0b), // depositor
                    address(0xb0b), // recipient
                    weth_(1), // inputToken
                    weth_(8453), // outputToken
                    0.5e18 * (1e18 + MockAcrossFFIConstants.VARIABLE_FEE_PCT) / 1e18 + MockAcrossFFIConstants.GAS_FEE, // inputAmount
                    0.5e18, // outputAmount
                    8453, // destinationChainId
                    address(0), // exclusiveRelayer
                    uint32(BLOCK_TIMESTAMP) - Across.QUOTE_TIMESTAMP_BUFFER, // quoteTimestamp
                    uint32(BLOCK_TIMESTAMP + Across.FILL_DEADLINE_BUFFER), // fillDeadline
                    0, // exclusivityDeadline
                    new bytes(0), // message
                    false // useNativeToken
                )
            ),
            "calldata is AcrossActions.depositV3(...);"
        );
        assertEq(
            result.quarkOperations[0].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
        );
        assertEq(result.quarkOperations[0].nonce, ALICE_DEFAULT_SECRET, "unexpected nonce");
        assertEq(result.quarkOperations[0].isReplayable, false, "isReplayable is false");

        assertEq(
            result.quarkOperations[1].scriptAddress,
            multicallAddress,
            "script address for Multicall is correct given the code jar address"
        );
        address[] memory callContracts = new address[](2);
        callContracts[0] = wrapperActionsAddress;
        callContracts[1] = transferActionsAddress;
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encodeWithSelector(
            WrapperActions.wrapAllETH.selector, TokenWrapper.getKnownWrapperTokenPair(8453, "WETH").wrapper
        );
        callDatas[1] = abi.encodeCall(TransferActions.transferERC20Token, (weth_(8453), address(0xceecee), 1e18));
        assertEq(
            result.quarkOperations[1].scriptCalldata,
            abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
            "calldata is Multicall.run([wrapperActionsAddress, transferActionsAddress], [WrapperActions.wrapAllETH(USDC_8453),  TransferActions.transferERC20Token(USDC_8453, address(0xceecee), 1e18))"
        );
        assertEq(
            result.quarkOperations[1].expiry, BLOCK_TIMESTAMP + 7 days, "expiry is current blockTimestamp + 7 days"
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
                    price: WETH_PRICE,
                    token: WETH_1,
                    assetSymbol: "WETH",
                    inputAmount: 0.5e18 * (1e18 + MockAcrossFFIConstants.VARIABLE_FEE_PCT) / 1e18
                        + MockAcrossFFIConstants.GAS_FEE,
                    outputAmount: 0.5e18,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_ACROSS
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.actions[1].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[1].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[1].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.TransferActionContext({
                    amount: 1e18,
                    price: WETH_PRICE,
                    token: WETH_8453,
                    assetSymbol: "WETH",
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

    function testSimpleBridgeWithAcrossTransferSucceeds() public {
        QuarkBuilder builder = new QuarkBuilder();
        // Note: There are 3e6 USDC on each chain, so the Builder should attempt to bridge 2 USDC to chain 8453
        QuarkBuilder.BuilderResult memory result = builder.transfer(
            TransferActionsBuilder.TransferIntent({
                assetSymbol: "USDC",
                chainId: 8453,
                amount: 5e6,
                sender: address(0xb0b),
                recipient: address(0xceecee),
                blockTimestamp: BLOCK_TIMESTAMP,
                preferAcross: true
            }), // transfer 5 USDC on chain 8453 to 0xceecee
            chainAccountsList_(6e6), // holding 6 USDC in total across chains 1, 8453
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
                                keccak256(type(AcrossActions).creationCode)
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
                AcrossActions.depositV3,
                (
                    0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5, // spokePool
                    address(0xb0b), // depositor
                    address(0xb0b), // recipient
                    address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), // inputToken
                    address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913), // outputToken
                    0x2e14e0, // inputAmount
                    0x1e8480, // outputAmount
                    8453, // destinationChainId
                    address(0), // exclusiveRelayer
                    uint32(BLOCK_TIMESTAMP) - 30 seconds, // quoteTimestamp
                    uint32(BLOCK_TIMESTAMP + 10 minutes), // fillDeadline
                    0, // exclusivityDeadline
                    new bytes(0), // message
                    false // useNativeToken
                )
            ),
            "calldata is AcrossActions.depositV3(...);"
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
                    inputAmount: 0x2e14e0,
                    outputAmount: 0x1e8480,
                    chainId: 1,
                    recipient: address(0xb0b),
                    destinationChainId: 8453,
                    bridgeType: Actions.BRIDGE_TYPE_ACROSS
                })
            ),
            "action context encoded from BridgeActionContext"
        );
        assertEq(result.actions[1].chainId, 8453, "operation is on chainid 8453");
        assertEq(result.actions[1].quarkAccount, address(0xb0b), "0xb0b sends the funds");
        assertEq(result.actions[1].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.actions[1].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.actions[1].paymentToken, address(0), "payment token is null");
        assertEq(result.actions[1].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(result.actions[1].nonceSecret, BOB_DEFAULT_SECRET, "unexpected nonce secret");
        assertEq(result.actions[1].totalPlays, 1, "total plays is 1");
        assertEq(
            result.actions[1].actionContext,
            abi.encode(
                Actions.TransferActionContext({
                    amount: 5e6,
                    price: USDC_PRICE,
                    token: USDC_8453,
                    assetSymbol: "USDC",
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
}
