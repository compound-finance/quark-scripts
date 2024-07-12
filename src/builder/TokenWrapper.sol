// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "./Strings.sol";
import {WrapperActions} from "../WrapperScripts.sol";

library TokenWrapper {
    error NotWrappable();
    error NotUnwrappable();

    struct KnownWrapperTokenPair {
        uint256 chainId;
        // The wrapper that perform wrapping/unwrapping actions
        // NOTE: Assume wrapper contract address = wrapped token contract address, as 99% of the time it is the case for wapper contracts
        address wrapper;
        string underlyingSymbol;
        // The underlying token address
        address underlyingToken;
        string wrappedSymbol;
    }

    function knownWrapperTokenPairs() internal pure returns (KnownWrapperTokenPair[] memory) {
        KnownWrapperTokenPair[] memory pairs = new KnownWrapperTokenPair[](3);
        pairs[0] = KnownWrapperTokenPair({
            chainId: 1,
            wrapper: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            underlyingSymbol: "ETH",
            underlyingToken: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            wrappedSymbol: "WETH"
        });
        pairs[1] = KnownWrapperTokenPair({
            chainId: 8453,
            wrapper: 0x4200000000000000000000000000000000000006,
            underlyingSymbol: "ETH",
            underlyingToken: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            wrappedSymbol: "WETH"
        });
        pairs[2] = KnownWrapperTokenPair({
            chainId: 11155111,
            wrapper: 0x2D5ee574e710219a521449679A4A7f2B43f046ad,
            underlyingSymbol: "ETH",
            underlyingToken: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            wrappedSymbol: "WETH"
        });
        // NOTE: Leave out stETH and wstETH auto wrapper for now
        // TODO: Need to figure a way out to compute the "correct" ratio between stETH and wstETH for QuarkBuilder
        // Because QuarkBuilder doesn't have access to on-chain data, but the ratio between stETH and wstETH is constantly changing,
        // which will be hard if we need to use it to compute the absolute number of wstETH to unwrap into stETH or vice versa
        //
        // pairs[2] = KnownWrapperTokenPair({
        //     chainId: 1,
        //     wrapper: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
        //     underlyingSymbol: "stETH",
        //     wrappedSymbol: "wstETH"
        // });
        return pairs;
    }

    function getKnownWrapperTokenPair(uint256 chainId, string memory tokenSymbol)
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
        return getKnownWrapperTokenPair(chainId, tokenSymbol).wrapper != address(0);
    }

    function getWrapperCounterpartSymbol(uint256 chainId, string memory assetSymbol)
        internal
        pure
        returns (string memory)
    {
        if (hasWrapperContract(chainId, assetSymbol)) {
            KnownWrapperTokenPair memory p = getKnownWrapperTokenPair(chainId, assetSymbol);
            if (isWrappedToken(chainId, assetSymbol)) {
                return p.underlyingSymbol;
            } else {
                return p.wrappedSymbol;
            }
        }

        // Return empty string if no counterpart
        return "";
    }

    function isWrappedToken(uint256 chainId, string memory tokenSymbol) internal pure returns (bool) {
        return Strings.stringEqIgnoreCase(tokenSymbol, getKnownWrapperTokenPair(chainId, tokenSymbol).wrappedSymbol);
    }

    function encodeActionToWrapOrUnwrap(uint256 chainId, string memory tokenSymbol, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        KnownWrapperTokenPair memory pair = getKnownWrapperTokenPair(chainId, tokenSymbol);
        if (isWrappedToken(chainId, tokenSymbol)) {
            return encodeActionToUnwrapToken(chainId, tokenSymbol, amount);
        } else {
            return encodeActionToWrapToken(chainId, tokenSymbol, pair.underlyingToken, amount);
        }
    }

    function encodeActionToWrapToken(uint256 chainId, string memory tokenSymbol, address tokenAddress, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        if (Strings.stringEqIgnoreCase(tokenSymbol, "ETH")) {
            return abi.encodeWithSelector(
                WrapperActions.wrapETH.selector, getKnownWrapperTokenPair(chainId, tokenSymbol).wrapper, amount
            );
        } else if (Strings.stringEqIgnoreCase(tokenSymbol, "stETH")) {
            return abi.encodeWithSelector(
                WrapperActions.wrapLidoStETH.selector,
                getKnownWrapperTokenPair(chainId, tokenSymbol).wrapper,
                tokenAddress,
                amount
            );
        }
        revert NotWrappable();
    }

    function encodeActionToUnwrapToken(uint256 chainId, string memory tokenSymbol, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        if (Strings.stringEqIgnoreCase(tokenSymbol, "WETH")) {
            return abi.encodeWithSelector(
                WrapperActions.unwrapWETH.selector, getKnownWrapperTokenPair(chainId, tokenSymbol).wrapper, amount
            );
        } else if (Strings.stringEqIgnoreCase(tokenSymbol, "wstETH")) {
            return abi.encodeWithSelector(
                WrapperActions.unwrapLidoWstETH.selector, getKnownWrapperTokenPair(chainId, tokenSymbol).wrapper, amount
            );
        }
        revert NotUnwrappable();
    }
}
