// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {Strings} from "./Strings.sol";

library PriceFeeds {
    error NoPriceFeedPathFound(string inputAssetSymbol, string outputAssetSymbol);

    struct PriceFeed {
        uint256 chainId;
        /// @dev The asset symbol for the base currency e.g. "ETH" in ETH/USD
        string baseSymbol;
        /// @dev The asset symbol for the quote currency e.g. "USD" in ETH/USD
        string quoteSymbol;
        address priceFeed;
    }

    /// @dev Addresses fetched from: https://docs.chain.link/data-feeds/price-feeds/addresses
    function knownPriceFeeds() internal pure returns (PriceFeed[] memory) {
        PriceFeed[] memory mainnetFeeds = knownPriceFeeds_1();
        PriceFeed[] memory baseFeeds = knownPriceFeeds_8453();
        PriceFeed[] memory sepoliaFeeds = knownPriceFeeds_11155111();
        PriceFeed[] memory baseSepoliaFeeds = knownPriceFeeds_84532();

        uint256 totalLength = mainnetFeeds.length + baseFeeds.length + sepoliaFeeds.length + baseSepoliaFeeds.length;
        PriceFeed[] memory allFeeds = new PriceFeed[](totalLength);

        uint256 currentIndex = 0;
        for (uint256 i = 0; i < mainnetFeeds.length; ++i) {
            allFeeds[currentIndex] = mainnetFeeds[i];
            currentIndex++;
        }
        for (uint256 i = 0; i < baseFeeds.length; ++i) {
            allFeeds[currentIndex] = baseFeeds[i];
            currentIndex++;
        }
        for (uint256 i = 0; i < sepoliaFeeds.length; ++i) {
            allFeeds[currentIndex] = sepoliaFeeds[i];
            currentIndex++;
        }
        for (uint256 i = 0; i < baseSepoliaFeeds.length; ++i) {
            allFeeds[currentIndex] = baseSepoliaFeeds[i];
            currentIndex++;
        }

        return allFeeds;
    }

    // Mainnet
    function knownPriceFeeds_1() internal pure returns (PriceFeed[] memory) {
        PriceFeed[] memory priceFeeds = new PriceFeed[](10);
        priceFeeds[0] = PriceFeed({
            chainId: 1,
            baseSymbol: "USDC",
            quoteSymbol: "ETH",
            priceFeed: 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4
        });
        priceFeeds[1] = PriceFeed({
            chainId: 1,
            baseSymbol: "ETH",
            quoteSymbol: "USD",
            priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        });
        priceFeeds[2] = PriceFeed({
            chainId: 1,
            baseSymbol: "LINK",
            quoteSymbol: "USD",
            priceFeed: 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c
        });
        priceFeeds[3] = PriceFeed({
            chainId: 1,
            baseSymbol: "LINK",
            quoteSymbol: "ETH",
            priceFeed: 0xDC530D9457755926550b59e8ECcdaE7624181557
        });
        priceFeeds[4] = PriceFeed({
            chainId: 1,
            baseSymbol: "wstETH",
            quoteSymbol: "USD",
            priceFeed: 0x164b276057258d81941e97B0a900D4C7B358bCe0
        });
        priceFeeds[5] = PriceFeed({
            chainId: 1,
            baseSymbol: "stETH",
            quoteSymbol: "ETH",
            priceFeed: 0x86392dC19c0b719886221c78AB11eb8Cf5c52812
        });
        priceFeeds[6] = PriceFeed({
            chainId: 1,
            baseSymbol: "rETH",
            quoteSymbol: "ETH",
            priceFeed: 0x536218f9E9Eb48863970252233c8F271f554C2d0
        });
        priceFeeds[7] = PriceFeed({
            chainId: 1,
            baseSymbol: "WBTC",
            quoteSymbol: "BTC",
            priceFeed: 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23
        });
        priceFeeds[8] = PriceFeed({
            chainId: 1,
            baseSymbol: "BTC",
            quoteSymbol: "USD",
            priceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c
        });
        priceFeeds[9] = PriceFeed({
            chainId: 1,
            baseSymbol: "BTC",
            quoteSymbol: "ETH",
            priceFeed: 0xdeb288F737066589598e9214E782fa5A8eD689e8
        });
        return priceFeeds;
    }

    // Base
    function knownPriceFeeds_8453() internal pure returns (PriceFeed[] memory) {
        PriceFeed[] memory priceFeeds = new PriceFeed[](5);
        priceFeeds[0] = PriceFeed({
            chainId: 8453,
            baseSymbol: "ETH",
            quoteSymbol: "USD",
            priceFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70
        });
        priceFeeds[1] = PriceFeed({
            chainId: 8453,
            baseSymbol: "LINK",
            quoteSymbol: "USD",
            priceFeed: 0x17CAb8FE31E32f08326e5E27412894e49B0f9D65
        });
        priceFeeds[2] = PriceFeed({
            chainId: 8453,
            baseSymbol: "LINK",
            quoteSymbol: "ETH",
            priceFeed: 0xc5E65227fe3385B88468F9A01600017cDC9F3A12
        });
        priceFeeds[3] = PriceFeed({
            chainId: 8453,
            baseSymbol: "cbETH",
            quoteSymbol: "USD",
            priceFeed: 0xd7818272B9e248357d13057AAb0B417aF31E817d
        });
        priceFeeds[4] = PriceFeed({
            chainId: 8453,
            baseSymbol: "cbETH",
            quoteSymbol: "ETH",
            priceFeed: 0x806b4Ac04501c29769051e42783cF04dCE41440b
        });
        return priceFeeds;
    }

    // Sepolia
    function knownPriceFeeds_11155111() internal pure returns (PriceFeed[] memory) {
        PriceFeed[] memory priceFeeds = new PriceFeed[](3);
        priceFeeds[0] = PriceFeed({
            chainId: 11155111,
            baseSymbol: "ETH",
            quoteSymbol: "USD",
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306
        });
        priceFeeds[1] = PriceFeed({
            chainId: 11155111,
            baseSymbol: "LINK",
            quoteSymbol: "USD",
            priceFeed: 0xc59E3633BAAC79493d908e63626716e204A45EdF
        });
        priceFeeds[2] = PriceFeed({
            chainId: 11155111,
            baseSymbol: "LINK",
            quoteSymbol: "ETH",
            priceFeed: 0x42585eD362B3f1BCa95c640FdFf35Ef899212734
        });
        return priceFeeds;
    }

    // Base Sepolia
    function knownPriceFeeds_84532() internal pure returns (PriceFeed[] memory) {
        PriceFeed[] memory priceFeeds = new PriceFeed[](3);
        priceFeeds[0] = PriceFeed({
            chainId: 84532,
            baseSymbol: "ETH",
            quoteSymbol: "USD",
            priceFeed: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1
        });
        priceFeeds[1] = PriceFeed({
            chainId: 84532,
            baseSymbol: "LINK",
            quoteSymbol: "USD",
            priceFeed: 0xb113F5A928BCfF189C998ab20d753a47F9dE5A61
        });
        priceFeeds[2] = PriceFeed({
            chainId: 84532,
            baseSymbol: "LINK",
            quoteSymbol: "ETH",
            priceFeed: 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69
        });
        return priceFeeds;
    }

    /// @dev Finds the price feed path that can convert the input asset to the output asset. We use a heuristics-based approach
    /// to find an appropriate path:
    /// Given an input asset IN and an output asset OUT
    /// 1. First, we check if IN/OUT or OUT/IN exists
    /// 2. Then, we check if there is a mutual asset that can be used to link IN and OUT, e.g. IN/ABC and ABC/OUT
    /// 3. If not, then we assume no price feed path exists
    function findPriceFeedPath(string memory inputAssetSymbol, string memory outputAssetSymbol, uint256 chainId)
        internal
        pure
        returns (address[] memory, bool[] memory)
    {
        PriceFeed[] memory inputAssetPriceFeeds = findPriceFeeds(inputAssetSymbol, chainId);
        PriceFeed[] memory outputAssetPriceFeeds = findPriceFeeds(outputAssetSymbol, chainId);

        for (uint256 i = 0; i < inputAssetPriceFeeds.length; ++i) {
            if (
                Strings.stringEqIgnoreCase(inputAssetSymbol, inputAssetPriceFeeds[i].baseSymbol)
                    && Strings.stringEqIgnoreCase(outputAssetSymbol, inputAssetPriceFeeds[i].quoteSymbol)
            ) {
                address[] memory path = new address[](1);
                bool[] memory reverse = new bool[](1);
                path[0] = inputAssetPriceFeeds[i].priceFeed;
                reverse[0] = false;
                return (path, reverse);
            } else if (
                Strings.stringEqIgnoreCase(inputAssetSymbol, inputAssetPriceFeeds[i].quoteSymbol)
                    && Strings.stringEqIgnoreCase(outputAssetSymbol, inputAssetPriceFeeds[i].baseSymbol)
            ) {
                address[] memory path = new address[](1);
                bool[] memory reverse = new bool[](1);
                path[0] = inputAssetPriceFeeds[i].priceFeed;
                reverse[0] = true;
                return (path, reverse);
            }
        }

        // Check if there is an indirect price feed path between the input and output asset
        // We only check for one-hop paths e.g. ETH/USD, USD/USDC
        // We only get here if no single price feed paths were found
        for (uint256 i = 0; i < inputAssetPriceFeeds.length; ++i) {
            for (uint256 j = 0; j < outputAssetPriceFeeds.length; ++j) {
                // e.g. ABC/IN and ABC/OUT -> We want IN/ABC and ABC/OUT, which equates to reverse=[true, false]
                if (Strings.stringEqIgnoreCase(inputAssetPriceFeeds[i].baseSymbol, outputAssetPriceFeeds[j].baseSymbol))
                {
                    address[] memory path = new address[](2);
                    bool[] memory reverse = new bool[](2);
                    path[0] = inputAssetPriceFeeds[i].priceFeed;
                    reverse[0] = true;
                    path[1] = outputAssetPriceFeeds[j].priceFeed;
                    reverse[1] = false;
                    return (path, reverse);
                } else if (
                    // e.g. IN/ABC and ABC/OUT -> We want IN/ABC and ABC/OUT, which equates to reverse=[false, false]
                    Strings.stringEqIgnoreCase(inputAssetPriceFeeds[i].quoteSymbol, outputAssetPriceFeeds[j].baseSymbol)
                ) {
                    address[] memory path = new address[](2);
                    bool[] memory reverse = new bool[](2);
                    path[0] = inputAssetPriceFeeds[i].priceFeed;
                    reverse[0] = false;
                    path[1] = outputAssetPriceFeeds[j].priceFeed;
                    reverse[1] = false;
                    return (path, reverse);
                } else if (
                    // e.g. ABC/IN and OUT/ABC -> We want IN/ABC and ABC/OUT, which equates to reverse=[true, true]
                    Strings.stringEqIgnoreCase(inputAssetPriceFeeds[i].baseSymbol, outputAssetPriceFeeds[j].quoteSymbol)
                ) {
                    address[] memory path = new address[](2);
                    bool[] memory reverse = new bool[](2);
                    path[0] = inputAssetPriceFeeds[i].priceFeed;
                    reverse[0] = true;
                    path[1] = outputAssetPriceFeeds[j].priceFeed;
                    reverse[1] = true;
                    return (path, reverse);
                } else if (
                    // e.g. IN/ABC and OUT/ABC -> We want IN/ABC and ABC/OUT, which equates to reverse=[false, true]
                    Strings.stringEqIgnoreCase(
                        inputAssetPriceFeeds[i].quoteSymbol, outputAssetPriceFeeds[j].quoteSymbol
                    )
                ) {
                    address[] memory path = new address[](2);
                    bool[] memory reverse = new bool[](2);
                    path[0] = inputAssetPriceFeeds[i].priceFeed;
                    reverse[0] = false;
                    path[1] = outputAssetPriceFeeds[j].priceFeed;
                    reverse[1] = true;
                    return (path, reverse);
                }
            }
        }

        revert NoPriceFeedPathFound(inputAssetSymbol, outputAssetSymbol);
    }

    function findPriceFeeds(string memory assetSymbol, uint256 chainId) internal pure returns (PriceFeed[] memory) {
        PriceFeed[] memory allPriceFeeds = knownPriceFeeds();
        uint256 count = 0;
        for (uint256 i = 0; i < allPriceFeeds.length; ++i) {
            if (allPriceFeeds[i].chainId == chainId) {
                if (
                    Strings.stringEqIgnoreCase(assetSymbol, allPriceFeeds[i].baseSymbol)
                        || Strings.stringEqIgnoreCase(assetSymbol, allPriceFeeds[i].quoteSymbol)
                ) {
                    count++;
                }
            }
        }

        PriceFeed[] memory result = new PriceFeed[](count);
        count = 0;
        for (uint256 i = 0; i < allPriceFeeds.length; ++i) {
            if (allPriceFeeds[i].chainId == chainId) {
                if (
                    Strings.stringEqIgnoreCase(assetSymbol, allPriceFeeds[i].baseSymbol)
                        || Strings.stringEqIgnoreCase(assetSymbol, allPriceFeeds[i].quoteSymbol)
                ) {
                    result[count++] = allPriceFeeds[i];
                }
            }
        }

        return result;
    }

    function convertToPriceFeedSymbol(string memory assetSymbol) internal pure returns (string memory) {
        if (Strings.stringEqIgnoreCase(assetSymbol, "WETH")) {
            return "ETH";
        } else if (Strings.stringEqIgnoreCase(assetSymbol, "USDC")) {
            return "USD";
        } else {
            return assetSymbol;
        }
    }
}
