// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {Strings} from "./Strings.sol";

library PaymentInfo {
    error NoKnownPaymentToken(uint256 chainId);
    error MaxCostMissingForChain(uint256 chainId);

    struct Payment {
        bool isToken;
        // Note: Payment `currency` should be the same across chains
        string currency;
        PaymentMaxCost[] maxCosts;
    }

    struct PaymentMaxCost {
        uint256 chainId;
        uint256 amount;
    }

    struct PaymentToken {
        uint256 chainId;
        string symbol;
        address token;
        address priceFeed;
    }

    function knownTokens() internal pure returns (PaymentToken[] memory) {
        PaymentToken[] memory paymentTokens = new PaymentToken[](2);
        paymentTokens[0] = PaymentToken({
            chainId: 1,
            symbol: "USDC",
            token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            // Pricefeed should be gas token to payment token
            // In this case, the mainnet uses ETH, and payment is USDC so we use ETH/USD price feed
            // TODO: To be more safer on USDC/USD peg, we might can consider creating our own proxy pricefeed by connecting ETH / USD => USDC / USD
            // (Unfortunately the off-the-shelf chainlink's pricefeed only has USDC / ETH, which also need a our own proxy pricefeed to convert it to ETH / USDC)
            priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        });
        paymentTokens[1] = PaymentToken({
            chainId: 8453,
            symbol: "USDC",
            token: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            priceFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70
        });
        return paymentTokens;
    }

    function knownToken(string memory tokenSymbol, uint256 chainId) internal pure returns (PaymentToken memory) {
        PaymentToken[] memory paymentTokens = knownTokens();
        for (uint256 i = 0; i < paymentTokens.length; ++i) {
            if (paymentTokens[i].chainId == chainId && Strings.stringEqIgnoreCase(tokenSymbol, paymentTokens[i].symbol))
            {
                return paymentTokens[i];
            }
        }
        revert NoKnownPaymentToken(chainId);
    }

    function findMaxCost(Payment memory payment, uint256 chainId) internal pure returns (uint256) {
        for (uint256 i = 0; i < payment.maxCosts.length; ++i) {
            if (payment.maxCosts[i].chainId == chainId) {
                return payment.maxCosts[i].amount;
            }
        }
        revert MaxCostMissingForChain(chainId);
    }
}
