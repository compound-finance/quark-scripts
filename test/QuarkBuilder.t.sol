// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {QuarkBuilder} from "../src/builder/QuarkBuilder.sol";
import {TransferActions} from "../src/DeFiScripts.sol";

contract QuarkBuilderTest is Test {
    function testInsufficientFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(QuarkBuilder.InsufficientFunds.selector);
        builder.transfer(
            transferUsdc_(1, 10_000_000, address(0xfe11a)), // transfer 1USDC on chain 1 to 0xfe11a
            chainAccountsList_(0e6), // but we are holding 0USDC on all chains
            paymentUsd_()
        );
    }

    function testMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(QuarkBuilder.MaxCostTooHigh.selector);
        builder.transfer(
            transferUsdc_(1, 1e6, address(0xfe11a)), // transfer 1USDC on chain 1 to 0xfe11a
            chainAccountsList_(2e6), // holding 2USDC
            paymentUsdc_(maxCosts_(1, 1_000_000_000)) // but costs 1,000USDC
        );
    }

    function testFundsUnavailable() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(QuarkBuilder.FundsUnavailable.selector);
        builder.transfer(
            // there is no bridge to chain 7777, so we cannot get to our funds
            transferUsdc_(7777, 2_000_000, address(0xfe11a)), // transfer 2USDC on chain 7777 to 0xfe11a
            chainAccountsList_(3_000_000), // holding 3USDC on chains 1, 8453
            paymentUsd_()
        );
    }

    function testTransferSucceedsLocally() public {
        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.transfer(
            // there is no bridge to chain 7777, so we cannot get to our funds
            transferUsdc_(1, 1_000_000, address(0xceecee)), // transfer 1 usdc on chain 1 to 0xceecee
            chainAccountsList_(3_000_000), // holding 3USDC on chains 1, 8453
            paymentUsd_()
        );

        assertEq(result.version, "1.0.0", "version 1");
        assertEq(result.paymentCurrency, "usd", "usd currency");

        // Check the quark operations
        assertEq(result.quarkOperations.length, 1, "one operation");
        assertEq(
            result.quarkOperations[0].scriptAddress,
             address(uint160(uint256(keccak256(abi.encodePacked(
                 bytes1(0xff),
                 /* codeJar address */ address(0xff),
                 uint256(0),
                 /* script bytecode */ keccak256(type(TransferActions).creationCode)
             ))))),
             "script address is correct given the code jar address on mainnet"
        );
        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(
                TransferActions.transferERC20Token,
                (usdc_(1), address(0xceecee), 1_000_000)
            ),
            "calldata is TransferActions.transferERC20Token(USDC_1, address(0xceecee), 1_000_000);"
        );

        // check the actions
        assertEq(result.quarkActions.length, 1, "one action");
        assertEq(result.quarkActions[0].chainId, 1, "operation is on chainid 1");
        assertEq(result.quarkActions[0].quarkAccount, address(0xa11ce), "0xa11ce sends the funds");
        assertEq(result.quarkActions[0].actionType, "TRANSFER", "action type is 'TRANSFER'");
        assertEq(result.quarkActions[0].paymentMethod, "OFFCHAIN", "payment method is 'OFFCHAIN'");
        assertEq(result.quarkActions[0].paymentToken, address(0), "payment token is null");
        assertEq(result.quarkActions[0].paymentMaxCost, 0, "payment has no max cost, since 'OFFCHAIN'");
        assertEq(
            result.quarkActions[0].actionContext,
            abi.encode(QuarkBuilder.TransferActionContext({
                amount: 1_000_000,
                price: 1_0000_0000,
                token: USDC_1,
                chainId: 1,
                recipient: address(0xceecee)
            })),
            "action context encoded from TransferActionContext"
        );

        // TODO: actually generate digests
        assertNotEq0(result.quarkOperationDigest, hex"", "non-empty single digest");
        assertNotEq0(result.multiQuarkOperationDigest, hex"", "non-empty single digest");
    }





    /**
     *
     * Fixture Functions
     *
     * @dev to avoid variable shadowing warnings and to provide a visual signifier when
     * a function call is used to mock some data, we suffix all of our fixture-generating
     * functions with a single underscore, like so: transferIntent_(...).
     */

    address constant USDC_1 = address(0xaa);
    address constant USDC_8453 = address(0xbb);

    function transferUsdc_(uint256 chainId, uint256 amount, address recipient)
        internal
        pure
        returns (QuarkBuilder.TransferIntent memory)
    {
        return QuarkBuilder.TransferIntent({
            chainId: chainId,
            sender: address(0xa11ce),
            recipient: recipient,
            amount: amount,
            assetSymbol: "USDC"
        });
    }

    function paymentUsdc_() internal pure returns (QuarkBuilder.Payment memory) {
        return paymentUsdc_(new QuarkBuilder.PaymentMaxCost[](0));
    }

    function paymentUsdc_(QuarkBuilder.PaymentMaxCost[] memory maxCosts) internal pure returns (QuarkBuilder.Payment memory) {
        return QuarkBuilder.Payment({
            isToken: true,
            currency: "usdc",
            maxCosts: maxCosts
        });
    }

    function paymentUsd_() internal pure returns (QuarkBuilder.Payment memory) {
        return paymentUsd_(new QuarkBuilder.PaymentMaxCost[](0));
    }

    function paymentUsd_(QuarkBuilder.PaymentMaxCost[] memory maxCosts) internal pure returns (QuarkBuilder.Payment memory) {
        return QuarkBuilder.Payment({
            isToken: false,
            currency: "usd",
            maxCosts: maxCosts
        });
    }

    function chainAccountsList_(uint256 amount) internal pure returns (QuarkBuilder.ChainAccounts[] memory) {
        QuarkBuilder.ChainAccounts[] memory chainAccountsList = new QuarkBuilder.ChainAccounts[](2);
        chainAccountsList[0] = QuarkBuilder.ChainAccounts({
            chainId: 1,
            quarkStates: quarkStates_(address(0xa11ce), 12),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), uint256(amount / 2))
        });
        chainAccountsList[1] = QuarkBuilder.ChainAccounts({
            chainId: 8453,
            quarkStates: quarkStates_(address(0xb0b), 2),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), uint256(amount / 2))
        });
        return chainAccountsList;
    }

    function quarkStates_() internal pure returns (QuarkBuilder.QuarkState[] memory) {
        QuarkBuilder.QuarkState[] memory quarkStates = new QuarkBuilder.QuarkState[](1);
        quarkStates[0] = quarkState_();
        return quarkStates;
    }

    function maxCosts_(uint256 chainId, uint256 amount) internal pure returns (QuarkBuilder.PaymentMaxCost[] memory) {
        QuarkBuilder.PaymentMaxCost[] memory maxCosts = new QuarkBuilder.PaymentMaxCost[](1);
        maxCosts[0] = QuarkBuilder.PaymentMaxCost({chainId: chainId, amount: amount});
        return maxCosts;
    }

    function assetPositionsList_(uint256 chainId, address account, uint256 balance)
        internal
        pure
        returns (QuarkBuilder.AssetPositions[] memory)
    {
        QuarkBuilder.AssetPositions[] memory assetPositionsList = new QuarkBuilder.AssetPositions[](1);
        assetPositionsList[0] = QuarkBuilder.AssetPositions({
            asset: usdc_(chainId),
            symbol: "USDC",
            decimals: 6,
            usdPrice: 1_0000_0000,
            accountBalances: accountBalances_(account, balance)
        });
        return assetPositionsList;
    }

    function accountBalances_(address account, uint256 balance) internal pure returns (QuarkBuilder.AccountBalance[] memory) {
        QuarkBuilder.AccountBalance[] memory accountBalances = new QuarkBuilder.AccountBalance[](1);
        accountBalances[0] = QuarkBuilder.AccountBalance({account: account, balance: balance});
        return accountBalances;
    }

    function usdc_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return USDC_1;
        if (chainId == 8453) return USDC_8453;
        revert("no mock usdc for that chain id bye");
    }

    function quarkStates_(address account, uint96 nextNonce) internal pure returns (QuarkBuilder.QuarkState[] memory) {
        QuarkBuilder.QuarkState[] memory quarkStates = new QuarkBuilder.QuarkState[](1);
        quarkStates[0] = quarkState_(account, nextNonce);
        return quarkStates;
    }

    function quarkState_() internal pure returns (QuarkBuilder.QuarkState memory) {
        return quarkState_(address(0xa11ce), 3);
    }

    function quarkState_(address account, uint96 nextNonce) internal pure returns (QuarkBuilder.QuarkState memory) {
        return QuarkBuilder.QuarkState({
            account: account,
            hasCode: true,
            isQuark: true,
            quarkVersion: "1",
            quarkNextNonce: nextNonce
        });
    }
}
