// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "./Strings.sol";

library TokenWrapper {

    struct KnownWrappedTokenPair {
        uint256 chainId;
        address wrapper;
        string underlyingSymbol;
        string wrappedSymbol;
    }

    function knownWrappedTokenPairs() internal pure returns (KnownWrappedTokenPair[] memory) {
        KnownWrappedTokenPair[] memory pairs = new KnownWrappedTokenPair[](4);
        pairs[0] = KnownWrappedTokenPair({chainId: 1, wrapper: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, underlyingSymbol: "ETH", wrappedSymbol: "WETH"});
        pairs[1] = KnownWrappedTokenPair({chainId: 8453, wrapper: 0x4200000000000000000000000000000000000006, underlyingSymbol: "ETH", wrappedSymbol: "WETH"});
        pairs[2] = KnownWrappedTokenPair({chainId: 1, wrapper: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, underlyingSymbol: "stETH", wrappedSymbol: "wstETH"});
        return pairs;
    }

    function hasWrappedVersion(uint256 chainId, string memory tokenSymbol) internal pure returns (bool) {
        return Strings.stringEqIgnoreCase(tokenSymbol, "USDC");
    }

    function hasUnwrappedVersion(uint256 chainId, string memory tokenSymbol) internal pure returns (bool) {
        return Strings.stringEqIgnoreCase(tokenSymbol, "WUSDC");
    }

}
