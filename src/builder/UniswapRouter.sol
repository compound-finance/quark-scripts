// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

library UniswapRouter {
    error NoKnownRouter(string routerType, uint256 chainId);

    struct RouterChain {
        uint256 chainId;
        address router;
    }

    /// @dev Addresses fetched from: https://docs.uniswap.org/contracts/v3/reference/deployments/
    /// Note: We use the addresses for SwapRouter, instead of SwapRouter02, which has a slightly different interface
    function knownChains() internal pure returns (RouterChain[] memory) {
        RouterChain[] memory chains = new RouterChain[](4);
        // Mainnet
        chains[0] = RouterChain({chainId: 1, router: 0xE592427A0AEce92De3Edee1F18E0157C05861564});
        // TODO: These chains don't have SwapRouter, so we will add them back once we move to SwapRouter02
        // Base
        // chains[1] = RouterChain({chainId: 8453, router: 0x2626664c2603336E57B271c5C0b26F421741e481});
        // Sepolia
        // chains[2] = RouterChain({chainId: 11155111, router: 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E});
        // Base Sepolia
        // chains[3] = RouterChain({chainId: 84532, router: 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4});
        return chains;
    }

    function knownChain(uint256 chainId) internal pure returns (RouterChain memory found) {
        RouterChain[] memory routerChains = knownChains();
        for (uint256 i = 0; i < routerChains.length; ++i) {
            if (routerChains[i].chainId == chainId) {
                return found = routerChains[i];
            }
        }
    }

    function knownRouter(uint256 chainId) internal pure returns (address) {
        RouterChain memory chain = knownChain(chainId);
        if (chain.router != address(0)) {
            return chain.router;
        } else {
            revert NoKnownRouter("Uniswap", chainId);
        }
    }
}
