// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

library MorphoWellKnown {
    error UnsupportedChainId();

    // Note: Current Morpho has same address across mainnet and base
    function getMorphoAddress() internal pure returns (address) {
        return 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    }

    // Note: Most Adaptive Curve IRM contracts has consistant address, but Morpho leaves it customizable
    function getAdaptiveCurveIrmAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) {
            return 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC; // Ethereum
        } else if (chainId == 8453) {
            return 0x46415998764C29aB2a25CbeA6254146D50D22687; // Base
        } else {
            revert UnsupportedChainId();
        }
    }

    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }
    
    function getMarketParams(string memory borrowAssetSymbol, string memory collateralAssetSymbol) internal pure returns () {

    }
}