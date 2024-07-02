// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "./Strings.sol";
import {IWETHActions, IWstETHActions} from "../WrapperScripts.sol";

library TokenWrapper {
    error NotWrappable();
    error NotUnwrappable();

    struct KnownWrapperTokenPair {
        uint256 chainId;
        address wrapper;
        string underlyingSymbol;
        string wrappedSymbol;
    }

    function knownWrapperTokenPairs() internal pure returns (KnownWrapperTokenPair[] memory) {
        KnownWrapperTokenPair[] memory pairs = new KnownWrapperTokenPair[](4);
        pairs[0] = KnownWrapperTokenPair({
            chainId: 1,
            wrapper: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            underlyingSymbol: "ETH",
            wrappedSymbol: "WETH"
        });
        pairs[1] = KnownWrapperTokenPair({
            chainId: 8453,
            wrapper: 0x4200000000000000000000000000000000000006,
            underlyingSymbol: "ETH",
            wrappedSymbol: "WETH"
        });
        pairs[2] = KnownWrapperTokenPair({
            chainId: 1,
            wrapper: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            underlyingSymbol: "stETH",
            wrappedSymbol: "wstETH"
        });
        return pairs;
    }

    function getWrapperContract(uint256 chainId, string memory tokenSymbol)
        internal
        pure
        returns (KnownWrapperTokenPair memory wrapper)
    {
        for (uint256 i = 0; i < knownWrapperTokenPairs().length; i++) {
            KnownWrapperTokenPair memory pair = knownWrapperTokenPairs()[i];
            if (
                pair.chainId == chainId
                    && (
                        Strings.stringEqIgnoreCase(tokenSymbol, pair.underlyingSymbol)
                            || Strings.stringEqIgnoreCase(tokenSymbol, pair.wrappedSymbol)
                    )
            ) {
                return wrapper = pair;
            }
        }
    }

    function hasWrapperContract(uint256 chainId, string memory tokenSymbol) internal pure returns (bool) {
        return getWrapperContract(chainId, tokenSymbol).wrapper != address(0);
    }

    function isWrappedToken(uint256 chainId, string memory tokenSymbol) internal pure returns (bool) {
        return Strings.stringEqIgnoreCase(tokenSymbol, getWrapperContract(chainId, tokenSymbol).wrappedSymbol);
    }

    function encodeWrapToken(uint256 chainId, string memory tokenSymbol, address tokenAddress, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        if (Strings.stringEqIgnoreCase(tokenSymbol, "ETH")) {
            return abi.encodeWithSelector(
                IWETHActions.wrapETH.selector, getWrapperContract(chainId, tokenSymbol).wrapper, amount
            );
        } else if (Strings.stringEqIgnoreCase(tokenSymbol, "stETH")) {
            return abi.encodeWithSelector(
                IWstETHActions.wrapLidoStETH.selector,
                getWrapperContract(chainId, tokenSymbol).wrapper,
                tokenAddress,
                amount
            );
        }
        revert NotWrappable();
    }

    function encodeUnwrapToken(uint256 chainId, string memory tokenSymbol, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        if (Strings.stringEqIgnoreCase(tokenSymbol, "WETH")) {
            return abi.encodeWithSelector(
                IWETHActions.unwrapWETH.selector, getWrapperContract(chainId, tokenSymbol).wrapper, amount
            );
        } else if (Strings.stringEqIgnoreCase(tokenSymbol, "wstETH")) {
            return abi.encodeWithSelector(
                IWstETHActions.unwrapLidoWstETH.selector, getWrapperContract(chainId, tokenSymbol).wrapper, amount
            );
        }
        revert NotUnwrappable();
    }
}
