// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilder, QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";

import {Actions} from "src/builder/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {CometSupplyActions, CometWithdrawActions, TransferActions} from "src/DeFiScripts.sol";
import {Paycall} from "src/Paycall.sol";

contract QuarkBuilderCometWithdrawTest is Test, QuarkBuilderTest {
    uint256 constant BLOCK_TIMESTAMP = 123_456_789;
    address constant COMET = address(0xc3);

    function cometWithdraw_(uint256 chainId, uint256 amount)
        internal
        pure
        returns (QuarkBuilder.CometWithdrawIntent memory)
    {
        return QuarkBuilder.CometWithdrawIntent({
            amount: amount,
            assetSymbol: "USDC",
            blockTimestamp: BLOCK_TIMESTAMP,
            chainId: chainId,
            comet: COMET,
            withdrawer: address(0xa11ce)
        });
    }

    // XXX test that you have enough of the asset to withdraw

    // XXX test cometWithdraw
    //   default path: withdrawing a token; paying with credit car
    function testCometWithdraw() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometWithdraw(
            cometWithdraw_(1, 1e6),
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
            paymentUsd_()
        );

        assertEq(result.version, "1.0.0", "version 1");
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
            abi.encodeCall(CometWithdrawActions.withdraw, (COMET, usdc_(1), 1e6)),
            "calldata is CometWithdrawActions.withdraw(COMET, usdc, 1e6);"
        );
        assertEq(
            result.quarkOperations[0].expiry,
            BLOCK_TIMESTAMP + 7 days,
            "expiry is current blockTimestamp + 7 days"
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
                    amount: 1e6,
                    // assetSymbol: "USDC",
                    chainId: 1,
                    comet: COMET,
                    price: 1e8
                    // token: USDC_1 XXX ?
                })
            ),
            "action context encoded from WithdrawActionContext"
        );

        // TODO: Check the contents of the EIP712 data
        assertNotEq(result.eip712Data.digest, hex"", "non-empty digest");
        assertNotEq(result.eip712Data.domainSeparator, hex"", "non-empty domain separator");
        assertNotEq(result.eip712Data.hashStruct, hex"", "non-empty hashStruct");
    }

    // XXX testCometWithdrawWithPaycall
    //   testing a withdraw of a non-payment token; paying with the operation with the pay token

    // XXX testCometWithdrawPayWithWithdraw
    //   testing that you can pay for the operation with the amount that you've withdrawn

    // XXX testCometWithdrawWithBridgeOfPaymentToken
    //   testing that you can pay for the withdraw with funds that have been bridged

    // XXX test that it reverts if the actions are not affordable
    // function testWithdrawMaxCostTooHigh() public {
    //     QuarkBuilder builder = new QuarkBuilder();
    //     vm.expectRevert(QuarkBuilder.MaxCostTooHigh.selector);
    //     builder.cometWithdraw(
    //         cometWithdraw_(1, 1e6),
    //         chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
    //         paymentUsdc_(maxCosts_(1, 1_000e6)) // but costs 1,000 USDC
    //     );
    // }
}
