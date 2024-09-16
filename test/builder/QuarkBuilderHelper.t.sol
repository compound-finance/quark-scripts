// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

import {QuarkBuilderHelper} from "src/builder/QuarkBuilderHelper.sol";

contract QuarkBuilderHelperTest is Test {
    function testCanBridgeUSDCOnSupportedChains() public {
        QuarkBuilderHelper helper = new QuarkBuilderHelper();

        assertEq(helper.canBridge(1, 8453, "USDC"), true);
    }

    function testCannotBridgeUSDCOnUnsupportedChains() public {
        QuarkBuilderHelper helper = new QuarkBuilderHelper();

        assertEq(helper.canBridge(999, 8453, "USDC"), false);
    }

    function testCannotBridgeUnsupportedAssets() public {
        QuarkBuilderHelper helper = new QuarkBuilderHelper();

        assertEq(helper.canBridge(1, 8453, "not_supported"), false);
    }

    function testAddBufferToPaymentCost() public {
        QuarkBuilderHelper helper = new QuarkBuilderHelper();

        assertEq(helper.addBufferToPaymentCost(0), 0);
        assertEq(helper.addBufferToPaymentCost(5_000_000), 6_000_000);
        assertEq(helper.addBufferToPaymentCost(98_384_506), 118_061_407);
    }
}
