// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

library UniswapRouter {
    error NoKnownRouter(string routerType, uint256 chainId);

    struct RouterChain {
        uint256 chainId;
        address router;
    }

    /// @dev Addresses fetched from: https://docs.uniswap.org/contracts/v3/reference/deployments/
    /// Note: Make sure that these are the addresses for SwapRouter02, not SwapRouter.
    function knownChains() internal pure returns (RouterChain[] memory) {
        RouterChain[] memory chains = new RouterChain[](6);
        // Mainnet
        chains[0] = RouterChain({chainId: 1, router: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45});
        // Base
        chains[1] = RouterChain({chainId: 8453, router: 0x2626664c2603336E57B271c5C0b26F421741e481});
        // Arbitrum
        chains[2] = RouterChain({chainId: 42161, router: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45});
        // Sepolia
        chains[3] = RouterChain({chainId: 11155111, router: 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E});
        // Base Sepolia
        chains[4] = RouterChain({chainId: 84532, router: 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4});
        // Arbitrum Sepolia
        chains[5] = RouterChain({chainId: 421614, router: 0x101F443B4d1b059569D643917553c771E1b9663E});
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
