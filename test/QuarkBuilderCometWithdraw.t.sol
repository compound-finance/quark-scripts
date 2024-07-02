// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilder, QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";

import {Actions} from "src/builder/Actions.sol";
import {CCTPBridgeActions} from "src/BridgeScripts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {CometSupplyActions, TransferActions} from "src/DeFiScripts.sol";
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

    // delete
    function testTest() public {
        assertEq(true, true);
    }

    // function cometWithdraw

    // testMaxCostTooHigh

    function testWithdrawMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(QuarkBuilder.MaxCostTooHigh.selector);
        builder.cometWithdraw(
            cometWithdraw_(1, 1e6),
            chainAccountsList_(2e6), // holding 2 USDC in total across 1, 8453
            paymentUsdc_(maxCosts_(1, 1_000e6)) // but costs 1,000 USDC
        );
    }


    // test assertions

    // confirm that you have enough of the token to withdraw

    // test cometWithdraw
    //   default path: withdrawing a token; paying with credit car

    // testCometWithdrawWithPaycall
    //   testing a withdraw of a non-payment token; paying with the operation with the pay token

    // testCometWithdrawPayWithWithdraw
    //   testing that you can pay for the operation with the amount that you've withdrawn

    // testCometWithdrawWithBridgeOfPaymentToken
    //   testing that you can pay for the withdraw with funds that have been bridged

}
