// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

library PaymentTokens {
    error NoKnownPaymentToken(uint256 chainId);

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
            priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        });
        paymentTokens[1] = PaymentToken({
            chainId: 8453,
            symbol: "USDC",
            token: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            priceFeed: 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B
        });
        return paymentTokens;
    }

    function knownToken(uint256 chainId) internal pure returns (PaymentToken memory) {
        PaymentToken[] memory paymentTokens = knownTokens();
        for (uint256 i = 0; i < paymentTokens.length; ++i) {
            if (paymentTokens[i].chainId == chainId) {
                return paymentTokens[i];
            }
        }
        revert NoKnownPaymentToken(chainId);
    }
}
