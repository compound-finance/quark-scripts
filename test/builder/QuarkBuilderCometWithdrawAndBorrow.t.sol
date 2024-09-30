// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Arrays} from "test/builder/lib/Arrays.sol";
import {Accounts, PaymentInfo, QuarkBuilder, QuarkBuilderTest} from "test/builder/lib/QuarkBuilderTest.sol";
import {CometWithdrawActions, CometSupplyMultipleAssetsAndBorrow} from "src/DeFiScripts.sol";
import {Multicall} from "src/Multicall.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";

contract QuarkBuilderCometWithdrawAndBorrowTest is Test, QuarkBuilderTest {
    function cometWithdrawAndBorrow_(
        uint256 chainId,
        address comet,
        string memory assetSymbol,
        uint256 amount,
        uint256[] memory collateralAmounts,
        string[] memory collateralAssetSymbols
    ) internal pure returns (QuarkBuilder.CometWithdrawAndBorrowIntent memory) {
        return QuarkBuilder.CometWithdrawAndBorrowIntent({
            amount: amount,
            assetSymbol: assetSymbol,
            blockTimestamp: BLOCK_TIMESTAMP,
            borrower: address(0xa11ce),
            chainId: chainId,
            collateralAmounts: collateralAmounts,
            collateralAssetSymbols: collateralAssetSymbols,
            comet: comet
        });
    }

    function testCometWithdrawAndBorrow() public {
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = 1e18;

        string[] memory collateralAssetSymbols = new string[](1);
        collateralAssetSymbols[0] = "LINK";

        ChainPortfolio[] memory chainPortfolios = new ChainPortfolio[](2);
        chainPortfolios[0] = ChainPortfolio({
            chainId: 1,
            account: address(0xa11ce),
            nextNonce: 12,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 10e18, 0), // user has 10 LINK
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });
        chainPortfolios[1] = ChainPortfolio({
            chainId: 8453,
            account: address(0xb0b),
            nextNonce: 2,
            assetSymbols: Arrays.stringArray("USDC", "USDT", "LINK", "WETH"),
            assetBalances: Arrays.uintArray(0, 0, 0, 0),
            cometPortfolios: emptyCometPortfolios_(),
            morphoPortfolios: emptyMorphoPortfolios_(),
            morphoVaultPortfolios: emptyMorphoVaultPortfolios_()
        });

        QuarkBuilder builder = new QuarkBuilder();
        QuarkBuilder.BuilderResult memory result = builder.cometWithdrawAndBorrow(
            cometWithdrawAndBorrow_(1, cometUsdc_(1), "USDC", 1e18, collateralAmounts, collateralAssetSymbols),
            chainAccountsFromChainPortfolios(chainPortfolios),
            paymentUsd_()
        );

        address withdrawScriptAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            /* codeJar address */
                            address(CodeJarHelper.CODE_JAR_ADDRESS),
                            uint256(0),
                            /* script bytecode */
                            keccak256(type(CometWithdrawActions).creationCode)
                        )
                    )
                )
            )
        );

        address borrowScriptAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            /* codeJar address */
                            address(CodeJarHelper.CODE_JAR_ADDRESS),
                            uint256(0),
                            /* script bytecode */
                            keccak256(type(CometSupplyMultipleAssetsAndBorrow).creationCode)
                        )
                    )
                )
            )
        );

        address[] memory multicallAddresses = new address[](2);
        multicallAddresses[0] = withdrawScriptAddress;
        multicallAddresses[1] = borrowScriptAddress;

        bytes[] memory multicallCalldata = new bytes[](2);
        multicallCalldata[0] =
            abi.encodeWithSelector(CometWithdrawActions.withdraw.selector, cometUsdc_(1), usdc_(1), type(uint256).max);
        multicallCalldata[1] = abi.encodeWithSelector(
            CometSupplyMultipleAssetsAndBorrow.run.selector,
            cometUsdc_(1),
            Arrays.addressArray(link_(1)),
            Arrays.uintArray(1e18),
            usdc_(1),
            1e18
        );

        assertEq(
            result.quarkOperations[0].scriptCalldata,
            abi.encodeCall(Multicall.run, (multicallAddresses, multicallCalldata)),
            "calldata is Multicall.run(withdraw, borrow)"
        );
    }
}
