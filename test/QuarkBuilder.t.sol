// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/builder/QuarkBuilder.sol";

contract QuarkBuilderTest is Test {
    function testInsufficientFunds() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(QuarkBuilder.InsufficientFunds.selector);
        builder.transfer(
            transferIntent(1, 10_000_000), // transfer 1USDC on chain 1
            chainAccountsList(0e6), // but we are holding 0USDC on all chains
            paymentUsd()
        );
    }

    function testMaxCostTooHigh() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(QuarkBuilder.MaxCostTooHigh.selector);
        builder.transfer(
            transferIntent(1, 1e6), // transfer 1USDC on chain 1
            chainAccountsList(2e6), // holding 2USDC
            paymentUsdc(maxCosts(1, 1_000_000_000)) // but costs 1,000USDC
        );
    }

    function testFundsUnavailable() public {
        QuarkBuilder builder = new QuarkBuilder();
        vm.expectRevert(QuarkBuilder.FundsUnavailable.selector);
        builder.transfer(
            // there is no bridge to chain 7777, so we cannot get to our funds
            transferIntent(7777, 2_000_000), // transfer 2USDC on chain 7777
            chainAccountsList(3_000_000), // holding 3USDC on chains 1, 8453
            paymentUsd()
        );
    }





    address constant USDC_1 = address(0xaa);
    address constant USDC_8453 = address(0xbb);

    function transferIntent(uint256 chainId, uint256 amount)
        internal
        pure
        returns (QuarkBuilder.TransferIntent memory)
    {
        return QuarkBuilder.TransferIntent({
            chainId: chainId,
            sender: address(0xa11ce),
            recipient: address(0xceecee),
            amount: amount,
            assetSymbol: "USDC"
        });
    }

    function paymentUsdc() internal pure returns (QuarkBuilder.Payment memory) {
        return paymentUsdc(new QuarkBuilder.PaymentMaxCost[](0));
    }

    function paymentUsdc(QuarkBuilder.PaymentMaxCost[] memory maxCosts) internal pure returns (QuarkBuilder.Payment memory) {
        return QuarkBuilder.Payment({
            isToken: true,
            currency: "usdc",
            maxCosts: maxCosts
        });
    }

    function paymentUsd() internal pure returns (QuarkBuilder.Payment memory) {
        return QuarkBuilder.Payment({
            isToken: false,
            currency: "usd",
            maxCosts: new QuarkBuilder.PaymentMaxCost[](0)
        });
    }

    function chainAccountsList(uint256 amount) internal pure returns (QuarkBuilder.ChainAccounts[] memory) {
        QuarkBuilder.ChainAccounts[] memory chainAccountsList = new QuarkBuilder.ChainAccounts[](2);
        chainAccountsList[0] = QuarkBuilder.ChainAccounts({
            chainId: 1,
            quarkStates: quarkStates(address(0xa11ce), 12),
            assetPositionsList: assetPositionsList(1, address(0xa11ce), uint256(amount / 2))
        });
        chainAccountsList[1] = QuarkBuilder.ChainAccounts({
            chainId: 8453,
            quarkStates: quarkStates(address(0xb0b), 2),
            assetPositionsList: assetPositionsList(8453, address(0xb0b), uint256(amount / 2))
        });
        return chainAccountsList;
    }

    function quarkStates() internal pure returns (QuarkBuilder.QuarkState[] memory) {
        QuarkBuilder.QuarkState[] memory quarkStates = new QuarkBuilder.QuarkState[](1);
        quarkStates[0] = quarkState();
        return quarkStates;
    }

    function maxCosts(uint256 chainId, uint256 amount) internal pure returns (QuarkBuilder.PaymentMaxCost[] memory) {
        QuarkBuilder.PaymentMaxCost[] memory maxCosts = new QuarkBuilder.PaymentMaxCost[](1);
        maxCosts[0] = QuarkBuilder.PaymentMaxCost({chainId: chainId, amount: amount});
        return maxCosts;
    }

    function assetPositionsList(uint256 chainId, address account, uint256 balance)
        internal
        pure
        returns (QuarkBuilder.AssetPositions[] memory)
    {
        QuarkBuilder.AssetPositions[] memory assetPositionsList = new QuarkBuilder.AssetPositions[](1);
        assetPositionsList[0] = QuarkBuilder.AssetPositions({
            asset: usdc(chainId),
            symbol: "USDC",
            decimals: 6,
            usdPrice: 1_0000_0000,
            accountBalances: accountBalances(account, balance)
        });
        return assetPositionsList;
    }

    function accountBalances(address account, uint256 balance) internal pure returns (QuarkBuilder.AccountBalance[] memory) {
        QuarkBuilder.AccountBalance[] memory accountBalances = new QuarkBuilder.AccountBalance[](1);
        accountBalances[0] = QuarkBuilder.AccountBalance({account: account, balance: balance});
        return accountBalances;
    }

    function usdc(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return USDC_1;
        if (chainId == 8453) return USDC_8453;
        revert("no mock usdc for that chain id bye");
    }

    function quarkStates(address account, uint96 nextNonce) internal pure returns (QuarkBuilder.QuarkState[] memory) {
        QuarkBuilder.QuarkState[] memory quarkStates = new QuarkBuilder.QuarkState[](1);
        quarkStates[0] = quarkState(account, nextNonce);
        return quarkStates;
    }

    function quarkState() internal pure returns (QuarkBuilder.QuarkState memory) {
        return quarkState(address(0xa11ce), 3);
    }

    function quarkState(address account, uint96 nextNonce) internal pure returns (QuarkBuilder.QuarkState memory) {
        return QuarkBuilder.QuarkState({
            account: account,
            hasCode: true,
            isQuark: true,
            quarkVersion: "1",
            quarkNextNonce: nextNonce
        });
    }
}
