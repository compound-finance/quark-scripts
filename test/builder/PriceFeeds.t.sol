// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {PriceFeeds} from "src/builder/PriceFeeds.sol";
import {Strings} from "src/builder/Strings.sol";

contract PriceFeedsTest is Test {
    address public constant USDC_ETH_PRICE_FEED = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    address public constant LINK_ETH_PRICE_FEED = 0xDC530D9457755926550b59e8ECcdaE7624181557;

    function testFindPriceFeeds() public {
        string memory assetSymbol = "ETH";
        uint256 chainId = 1;
        PriceFeeds.PriceFeed[] memory priceFeeds = PriceFeeds.findPriceFeeds(assetSymbol, chainId);

        assertEq(priceFeeds.length, 3);
        for (uint256 i = 0; i < priceFeeds.length; ++i) {
            // Check that ETH is either the baseSymbol or the quoteSymbol in each price feed
            bool isBaseOrQuoteSymbol = Strings.stringEq(priceFeeds[i].baseSymbol, assetSymbol)
                || Strings.stringEq(priceFeeds[i].quoteSymbol, assetSymbol);

            assertEq(priceFeeds[i].chainId, 1);
            assertTrue(isBaseOrQuoteSymbol);
        }
    }

    function testFindPriceFeedPathDirectMatch() public {
        string memory inputAssetSymbol = "USDC";
        string memory outputAssetSymbol = "ETH";
        uint256 chainId = 1;
        (address[] memory path, bool[] memory reverse) =
            PriceFeeds.findPriceFeedPath(inputAssetSymbol, outputAssetSymbol, chainId);

        // Assert
        assertEq(path.length, 1);
        assertEq(path[0], USDC_ETH_PRICE_FEED);
        assertEq(reverse[0], false);
    }

    function testFindPriceFeedPathDirectMatchWithReverse() public {
        string memory inputAssetSymbol = "ETH";
        string memory outputAssetSymbol = "USDC";
        uint256 chainId = 1;
        (address[] memory path, bool[] memory reverse) =
            PriceFeeds.findPriceFeedPath(inputAssetSymbol, outputAssetSymbol, chainId);

        // Assert
        assertEq(path.length, 1);
        assertEq(path[0], USDC_ETH_PRICE_FEED);
        assertEq(reverse[0], true);
    }

    function testFindPriceFeedPathOneHopMatch() public {
        string memory inputAssetSymbol = "LINK";
        string memory outputAssetSymbol = "USDC";
        uint256 chainId = 1;
        (address[] memory path, bool[] memory reverse) =
            PriceFeeds.findPriceFeedPath(inputAssetSymbol, outputAssetSymbol, chainId);

        assertEq(path.length, 2);
        assertEq(path[0], LINK_ETH_PRICE_FEED);
        assertEq(reverse[0], false);
        assertEq(path[1], USDC_ETH_PRICE_FEED);
        assertEq(reverse[1], true);
    }

    function testFindPriceFeedPathNoMatch() public {
        string memory inputAssetSymbol = "BTC";
        string memory outputAssetSymbol = "USDT";
        uint256 chainId = 1;

        vm.expectRevert(
            abi.encodeWithSelector(PriceFeeds.NoPriceFeedPathFound.selector, inputAssetSymbol, outputAssetSymbol)
        );
        PriceFeeds.findPriceFeedPath(inputAssetSymbol, outputAssetSymbol, chainId);
    }
}
