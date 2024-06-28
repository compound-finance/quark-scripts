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
        pairs[0] = KnownWrappedTokenPair({chainId: 1, wrapper: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, underlyingSymbol: "ETH", wrappedSymbol: "WETH"});
        pairs[1] = KnownWrappedTokenPair({chainId: 8453, wrapper: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, underlyingSymbol: "ETH", wrappedSymbol: "WETH"});
        pairs[2] = KnownWrappedTokenPair({chainId: 1, wrapper: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, underlyingSymbol: "ETH", wrappedSymbol: "WETH"});
        pairs[3] = KnownWrappedTokenPair({chainId: 8453, wrapper: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, underlyingSymbol: "ETH", wrappedSymbol: "WETH"});
        return pairs;
    }

    function hasWrappedVersion(string memory tokenSymbol) internal pure returns (bool) {
        return Strings.stringEqIgnoreCase(tokenSymbol, "USDC");
    }

    function hasUnwrappedVersion(string memory tokenSymbol) internal pure returns (bool) {
        return Strings.stringEqIgnoreCase(tokenSymbol, "WUSDC");
    }

}
