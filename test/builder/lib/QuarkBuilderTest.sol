// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Accounts} from "src/builder/Accounts.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {Paycall} from "src/Paycall.sol";
import {Quotecall} from "src/Quotecall.sol";
import {PaymentInfo} from "src/builder/PaymentInfo.sol";
import {QuarkBuilder} from "src/builder/QuarkBuilder.sol";
import {Strings} from "src/builder/Strings.sol";

import {Arrays} from "test/builder/lib/Arrays.sol";

contract QuarkBuilderTest {
    uint256 constant BLOCK_TIMESTAMP = 123_456_789;

    address constant COMET_1_USDC = address(0xc3010a);
    address constant COMET_1_WETH = address(0xc3010b);
    address constant COMET_8453_USDC = address(0xc384530a);
    address constant COMET_8453_WETH = address(0xc384530b);

    address constant LINK_1 = address(0xfeed01);
    address constant LINK_7777 = address(0xfeed7777);
    address constant LINK_8453 = address(0xfeed8453);
    uint256 constant LINK_PRICE = 14e8;

    address constant USDC_1 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_7777 = 0x8D89c5CaA76592e30e0410B9e68C0f235c62B312;
    address constant USDC_8453 = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 constant USDC_PRICE = 1e8;

    address constant USDT_1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDT_7777 = address(0xDEADBEEF);
    address constant USDT_8453 = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    uint256 constant USDT_PRICE = 1e8;

    address constant WETH_1 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WETH_7777 = address(0xDEEDBEEF);
    address constant WETH_8453 = 0x4200000000000000000000000000000000000006;
    uint256 constant WETH_PRICE = 3000e8;

    address constant ETH_USD_PRICE_FEED_1 = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant ETH_USD_PRICE_FEED_8453 = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    /**
     *
     * Fixture Functions
     *
     * @dev to avoid variable shadowing warnings and to provide a visual signifier when
     * a function call is used to mock some data, we suffix all of our fixture-generating
     * functions with a single underscore, like so: transferIntent_(...).
     */
    function paymentUsdc_() internal pure returns (PaymentInfo.Payment memory) {
        return paymentUsdc_(new PaymentInfo.PaymentMaxCost[](0));
    }

    function paymentUsdc_(PaymentInfo.PaymentMaxCost[] memory maxCosts)
        internal
        pure
        returns (PaymentInfo.Payment memory)
    {
        return PaymentInfo.Payment({isToken: true, currency: "usdc", maxCosts: maxCosts});
    }

    function paymentUsd_() internal pure returns (PaymentInfo.Payment memory) {
        return paymentUsd_(new PaymentInfo.PaymentMaxCost[](0));
    }

    function paymentUsd_(PaymentInfo.PaymentMaxCost[] memory maxCosts)
        internal
        pure
        returns (PaymentInfo.Payment memory)
    {
        return PaymentInfo.Payment({isToken: false, currency: "usd", maxCosts: maxCosts});
    }

    // TODO: refactor
    function chainAccountsList_(uint256 amount) internal pure returns (Accounts.ChainAccounts[] memory) {
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](3);
        chainAccountsList[0] = Accounts.ChainAccounts({
            chainId: 1,
            quarkStates: quarkStates_(address(0xa11ce), 12),
            assetPositionsList: assetPositionsList_(1, address(0xa11ce), uint256(amount / 2)),
            cometPositions: emptyCometPositions_(), 
            morphoBluePositions: emptyMorphoBluePositions_()
        });
        chainAccountsList[1] = Accounts.ChainAccounts({
            chainId: 8453,
            quarkStates: quarkStates_(address(0xb0b), 2),
            assetPositionsList: assetPositionsList_(8453, address(0xb0b), uint256(amount / 2)),
            cometPositions: emptyCometPositions_(),
            morphoBluePositions: emptyMorphoBluePositions_()
        });
        chainAccountsList[2] = Accounts.ChainAccounts({
            chainId: 7777,
            quarkStates: quarkStates_(address(0xc0b), 5),
            assetPositionsList: assetPositionsList_(7777, address(0xc0b), uint256(0)),
            cometPositions: emptyCometPositions_(),
            morphoBluePositions: emptyMorphoBluePositions_()
        });
        return chainAccountsList;
    }

    function emptyCometPositions_() internal pure returns (Accounts.CometPositions[] memory) {
        Accounts.CometPositions[] memory emptyCometPositions = new Accounts.CometPositions[](0);
        return emptyCometPositions;
    }

    function emptyMorphoBluePositions_() internal pure returns (Accounts.MorphoBluePositions[] memory) {
        Accounts.MorphoBluePositions[] memory emptyMorphoBluePositions = new Accounts.MorphoBluePositions[](0);
        return emptyMorphoBluePositions;
    }

    function quarkStates_() internal pure returns (Accounts.QuarkState[] memory) {
        Accounts.QuarkState[] memory quarkStates = new Accounts.QuarkState[](1);
        quarkStates[0] = quarkState_();
        return quarkStates;
    }

    function maxCosts_(uint256 chainId, uint256 amount) internal pure returns (PaymentInfo.PaymentMaxCost[] memory) {
        PaymentInfo.PaymentMaxCost[] memory maxCosts = new PaymentInfo.PaymentMaxCost[](1);
        maxCosts[0] = PaymentInfo.PaymentMaxCost({chainId: chainId, amount: amount});
        return maxCosts;
    }

    function assetPositionsList_(uint256 chainId, address account, uint256 balance)
        internal
        pure
        returns (Accounts.AssetPositions[] memory)
    {
        Accounts.AssetPositions[] memory assetPositionsList = new Accounts.AssetPositions[](4);
        assetPositionsList[0] = Accounts.AssetPositions({
            asset: usdc_(chainId),
            symbol: "USDC",
            decimals: 6,
            usdPrice: USDC_PRICE,
            accountBalances: accountBalances_(account, balance)
        });
        assetPositionsList[1] = Accounts.AssetPositions({
            asset: usdt_(chainId),
            symbol: "USDT",
            decimals: 6,
            usdPrice: USDT_PRICE,
            accountBalances: accountBalances_(account, balance)
        });
        assetPositionsList[2] = Accounts.AssetPositions({
            asset: weth_(chainId),
            symbol: "WETH",
            decimals: 18,
            usdPrice: WETH_PRICE,
            accountBalances: accountBalances_(account, 0)
        });
        assetPositionsList[3] = Accounts.AssetPositions({
            asset: link_(chainId),
            symbol: "LINK",
            decimals: 18,
            usdPrice: LINK_PRICE,
            accountBalances: accountBalances_(account, 0) // empty balance
        });
        return assetPositionsList;
    }

    function accountBalances_(address account, uint256 balance)
        internal
        pure
        returns (Accounts.AccountBalance[] memory)
    {
        Accounts.AccountBalance[] memory accountBalances = new Accounts.AccountBalance[](1);
        accountBalances[0] = Accounts.AccountBalance({account: account, balance: balance});
        return accountBalances;
    }

    function link_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return LINK_1;
        if (chainId == 7777) return LINK_7777; // Mock with random chain's LINK
        if (chainId == 8453) return LINK_8453;
        revert("no mock LINK for chain id");
    }

    function usdc_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return USDC_1;
        if (chainId == 8453) return USDC_8453;
        if (chainId == 7777) return USDC_7777; // Mock with random chain's USDC
        revert("no mock usdc for that chain id bye");
    }

    function usdt_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return USDT_1;
        if (chainId == 8453) return USDT_8453;
        if (chainId == 7777) return USDT_7777; // Mock with random chain's USDT
        revert("no mock usdt for that chain id bye");
    }

    function eth_() internal pure returns (address) {
        return 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

    function weth_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return WETH_1;
        if (chainId == 8453) return WETH_8453;
        if (chainId == 7777) return WETH_7777; // Mock with random chain's WETH
        revert("no mock weth for that chain id bye");
    }

    function paycallUsdc_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) {
            return CodeJarHelper.getCodeAddress(
                abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
            );
        } else if (chainId == 8453) {
            return CodeJarHelper.getCodeAddress(
                abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
            );
        } else {
            revert("no paycall address for chain id");
        }
    }

    function quotecallUsdc_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) {
            return CodeJarHelper.getCodeAddress(
                abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_1, USDC_1))
            );
        } else if (chainId == 8453) {
            return CodeJarHelper.getCodeAddress(
                abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED_8453, USDC_8453))
            );
        } else {
            revert("no quotecall address for chain id");
        }
    }

    function cometUsdc_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) {
            return COMET_1_USDC;
        } else if (chainId == 8453) {
            return COMET_8453_USDC;
        } else {
            revert("no USDC Comet for chain id");
        }
    }

    function cometWeth_(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) {
            return COMET_1_WETH;
        } else if (chainId == 8453) {
            return COMET_8453_WETH;
        } else {
            revert("no WETH Comet for chain id");
        }
    }

    function quarkStates_(address account, uint96 nextNonce) internal pure returns (Accounts.QuarkState[] memory) {
        Accounts.QuarkState[] memory quarkStates = new Accounts.QuarkState[](1);
        quarkStates[0] = quarkState_(account, nextNonce);
        return quarkStates;
    }

    function quarkState_() internal pure returns (Accounts.QuarkState memory) {
        return quarkState_(address(0xa11ce), 3);
    }

    function quarkState_(address account, uint96 nextNonce) internal pure returns (Accounts.QuarkState memory) {
        return Accounts.QuarkState({account: account, quarkNextNonce: nextNonce});
    }

    struct ChainPortfolio {
        uint256 chainId;
        address account;
        uint96 nextNonce;
        string[] assetSymbols;
        uint256[] assetBalances;
        CometPortfolio[] cometPortfolios;
        MorphoBluePortfolio[] morphoBluePortfolios;
    }

    struct CometPortfolio {
        address comet;
        uint256 baseSupplied;
        uint256 baseBorrowed;
        string[] collateralAssetSymbols;
        uint256[] collateralAssetBalances;
    }

    struct MorphoBluePortfolio {
        bytes32 marketId;
        address morpho;
        address loanToken;
        address collateralToken;
        uint256 borrowedBalance;
        uint256 borrowedShares;
        uint256 collateralBalance;
    }

    function emptyCometPortfolios_() internal pure returns (CometPortfolio[] memory) {
        CometPortfolio[] memory emptyCometPortfolios = new CometPortfolio[](0);
        return emptyCometPortfolios;
    }

    function emptyMorphoBluePortfolios_() internal pure returns (MorphoBluePortfolio[] memory) {
        MorphoBluePortfolio[] memory emptyMorphoBluePortfolios = new MorphoBluePortfolio[](0);
        return emptyMorphoBluePortfolios;
    }

    function chainAccountsFromChainPortfolios(ChainPortfolio[] memory chainPortfolios)
        internal
        pure
        returns (Accounts.ChainAccounts[] memory)
    {
        Accounts.ChainAccounts[] memory chainAccountsList = new Accounts.ChainAccounts[](chainPortfolios.length);
        for (uint256 i = 0; i < chainPortfolios.length; ++i) {
            chainAccountsList[i] = Accounts.ChainAccounts({
                chainId: chainPortfolios[i].chainId,
                quarkStates: quarkStates_(chainPortfolios[i].account, chainPortfolios[i].nextNonce),
                assetPositionsList: assetPositionsForAssets(
                    chainPortfolios[i].chainId,
                    chainPortfolios[i].account,
                    chainPortfolios[i].assetSymbols,
                    chainPortfolios[i].assetBalances
                    ),
                // cometPositions: cometPositionsFor
                cometPositions: cometPositionsForCometPorfolios(
                    chainPortfolios[i].chainId, chainPortfolios[i].account, chainPortfolios[i].cometPortfolios
                    ), 
                morphoBluePositions: morphoBluePositionsForMorphoBluePortfolios(
                    chainPortfolios[i].chainId, chainPortfolios[i].account, chainPortfolios[i].morphoBluePortfolios
                    )
            });
        }

        return chainAccountsList;
    }

    function cometPositionsForCometPorfolios(uint256 chainId, address account, CometPortfolio[] memory cometPortfolios)
        internal
        pure
        returns (Accounts.CometPositions[] memory)
    {
        Accounts.CometPositions[] memory cometPositions = new Accounts.CometPositions[](cometPortfolios.length);

        for (uint256 i = 0; i < cometPortfolios.length; ++i) {
            CometPortfolio memory cometPortfolio = cometPortfolios[i];
            Accounts.CometCollateralPosition[] memory collateralPositions =
                new Accounts.CometCollateralPosition[](cometPortfolio.collateralAssetSymbols.length);

            for (uint256 j = 0; j < cometPortfolio.collateralAssetSymbols.length; ++j) {
                (address asset,,) = assetInfo(cometPortfolio.collateralAssetSymbols[j], chainId);
                collateralPositions[j] = Accounts.CometCollateralPosition({
                    asset: asset,
                    accounts: Arrays.addressArray(account),
                    balances: Arrays.uintArray(cometPortfolio.collateralAssetBalances[j])
                });
            }

            cometPositions[i] = Accounts.CometPositions({
                comet: cometPortfolio.comet,
                basePosition: Accounts.CometBasePosition({
                    asset: baseAssetForComet(chainId, cometPortfolio.comet),
                    accounts: Arrays.addressArray(account),
                    borrowed: Arrays.uintArray(cometPortfolio.baseBorrowed),
                    supplied: Arrays.uintArray(cometPortfolio.baseSupplied)
                }),
                collateralPositions: collateralPositions
            });
        }

        return cometPositions;
    }

    function morphoBluePositionsForMorphoBluePortfolios(
        uint256 chainId,
        address account,
        MorphoBluePortfolio[] memory morphoBluePortfolios
    ) internal pure returns (Accounts.MorphoBluePositions[] memory) {
        Accounts.MorphoBluePositions[] memory morphoBluePositions = new Accounts.MorphoBluePositions[](morphoBluePortfolios.length);

        for (uint256 i = 0; i < morphoBluePortfolios.length; ++i) {
            MorphoBluePortfolio memory morphoBluePortfolio = morphoBluePortfolios[i];
            morphoBluePositions[i] = Accounts.MorphoBluePositions({
                marketId: morphoBluePortfolio.marketId,
                morpho: morphoBluePortfolio.morpho,
                loanToken: morphoBluePortfolio.loanToken,
                collateralToken: morphoBluePortfolio.collateralToken,
                borrowPosition: Accounts.MorphoBlueBorrowPosition({
                    accounts: Arrays.addressArray(account),
                    borrowedBalances: Arrays.uintArray(morphoBluePortfolio.borrowedBalance),
                    borrowedShares: Arrays.uintArray(morphoBluePortfolio.borrowedShares)
                }),
                collateralPosition: Accounts.MorphoBlueCollateralPosition({
                    accounts: Arrays.addressArray(account),
                    collateralBalances: Arrays.uintArray(morphoBluePortfolio.collateralBalance)
                })
            });
        }

        return morphoBluePositions;
    }

    function baseAssetForComet(uint256 chainId, address comet) internal pure returns (address) {
        if (comet == COMET_1_USDC || comet == COMET_8453_USDC) {
            return usdc_(chainId);
        } else if (comet == COMET_1_WETH || comet == COMET_8453_WETH) {
            return weth_(chainId);
        } else {
            revert("unknown chainId/comet combination");
        }
    }

    function assetPositionsForAssets(
        uint256 chainId,
        address account,
        string[] memory assetSymbols,
        uint256[] memory assetBalances
    ) internal pure returns (Accounts.AssetPositions[] memory) {
        Accounts.AssetPositions[] memory assetPositionsList = new Accounts.AssetPositions[](assetSymbols.length);

        for (uint256 i = 0; i < assetSymbols.length; ++i) {
            (address asset, uint256 decimals, uint256 price) = assetInfo(assetSymbols[i], chainId);
            assetPositionsList[i] = Accounts.AssetPositions({
                asset: asset,
                symbol: assetSymbols[i],
                decimals: decimals,
                usdPrice: price,
                accountBalances: accountBalances_(account, assetBalances[i])
            });
        }

        return assetPositionsList;
    }

    function assetInfo(string memory assetSymbol, uint256 chainId) internal pure returns (address, uint256, uint256) {
        if (Strings.stringEq(assetSymbol, "USDC")) {
            return (usdc_(chainId), 6, USDC_PRICE);
        } else if (Strings.stringEq(assetSymbol, "USDT")) {
            return (usdt_(chainId), 6, USDT_PRICE);
        } else if (Strings.stringEq(assetSymbol, "WETH")) {
            return (weth_(chainId), 18, WETH_PRICE);
        } else if (Strings.stringEq(assetSymbol, "ETH")) {
            return (eth_(), 18, WETH_PRICE);
        } else if (Strings.stringEq(assetSymbol, "LINK")) {
            return (link_(chainId), 18, LINK_PRICE);
        } else {
            revert("unknown assetSymbol");
        }
    }
}
