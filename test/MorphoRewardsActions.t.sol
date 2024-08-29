// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin/interfaces/IERC20.sol";
import {IMorpho, MarketParams, Position} from "src/interfaces/IMorpho.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {YulHelper} from "./lib/YulHelper.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";

import {DeFiScriptErrors} from "src/lib/DeFiScriptErrors.sol";

import "src/DeFiScripts.sol";
import "src/defi_integrations/MorphoScripts.sol";

/**
 * Tests for Morpho Rewards Claim
 */
contract MorphoRewardsActionsTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant morphoBlue = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant adaptiveCurveIrm = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant morphoOracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    MarketParams marketParams = MarketParams(USDC, wstETH, morphoOracle, adaptiveCurveIrm, 0.86e18);
    bytes morphoRewardsActionsScripts = new YulHelper().getCode("MorphoScripts.sol/MorphoRewardsActions.json");
    bytes morphoBlueActionsScripts = new YulHelper().getCode("MorphoScripts.sol/MorphoBlueActions.json");

    // Just a list of data from Morpho rewards api for ease of testing on sample account
    address sampleAccount = 0x87E0b41CB4d65d788f08c8D82589eA7923D73BA5;
    address[] distributors = [0x330eefa8a787552DC5cAd3C3cA644844B1E61Ddb, 0x330eefa8a787552DC5cAd3C3cA644844B1E61Ddb];
    address[] accounts = [sampleAccount, sampleAccount];
    address[] rewards = [0xc55126051B22eBb829D00368f4B12Bde432de5Da, 0xdAC17F958D2ee523a2206206994597C13D831ec7];
    uint256[] claimables = [547387349612, 116];
    bytes32[][] proofs = [
        [
            bytes32(0xce63a4c1fabb68437d0e5edc21b732c5a215f1c5a9ed6a52902f0415e148cc0a),
            bytes32(0x23b2ad869c44ff4946d49f0e048edd1303f0cef3679d3e21143c4cfdcde97f20),
            bytes32(0x937a82a4d574f809052269e6d4a5613fa4ce333064d012e96e9cc3c04fee7a9c),
            bytes32(0xf93fea78509a3b4fe28d963d965ab8819bbf6c08f5789bddde16127e98e6f696),
            bytes32(0xbb53cefdee57ab5a04a7be61a15c1ea00beacd0a4adb132dd2e046582eafbec8),
            bytes32(0x3dcb507af99e19c829fc2f5a8f57418258230818d4db8dc3080e5cafff5bfd3c),
            bytes32(0xca3e0c0cc07c55a02cbc21313bbd9a4d27dae6a28580fbd7dfad74216d4edac3),
            bytes32(0x59bdab6ff3d8cd5c682ff241da1d56e9bba6f5c0a739c28629c10ffab8bb9c95),
            bytes32(0x56a6fd126541d4a6b4902b78125db2c92b3b9cfb3249bbe3681cc2ccf9a6aa2c),
            bytes32(0xfcfad3b73969b50e0369e94db6fcd9301b5e776784620a09c0b52a5cf3326f2b),
            bytes32(0x7ee3c650dc15c36a6a0284c40b61391f7ac07f57d50802d92d2ccb7a19ff9dbb)
        ],
        [
            bytes32(0x7ac5a364f8e3d902a778e6f22d9800304bce9a24108a6b375e9d7afffa586648),
            bytes32(0xd0e2f9d70a7c8ddfe74cf2e922067421f06af4c16da32c13d13e6226aff54772),
            bytes32(0x8417ffe0c1e153c75ad3bf85f8d52b22ebc5370deda637231cb7fef3238d60b7),
            bytes32(0x99baa8011e519a6650c7f8887edde764c9198973be390dfad9a43e8af4603326),
            bytes32(0x7db554929334c43f06c93b0917a22765ba0b27684eb3bdbb09eefaad665cf51f),
            bytes32(0xd35638edfe77f64712acd397cfddd12da5ba480d05d77b52fa5f9f930b8c4a11),
            bytes32(0xee0010ba447e3edda1a034acc142e66ce5c772dc9cbbdf86044e5ee760d4159f),
            bytes32(0xedca6a5e9ba49d334eebdc4167e1730fcce5c7e4bbc17638c1cb6b4c42e85e9b),
            bytes32(0xfd8786de55c7c2e69c4ede4fe80b5d696875621b7aea7f29736451d3ea667427),
            bytes32(0xff695c9c3721e77a593d67cf0cbea7d495d0120ed51e31ab1428a7251665ce37),
            bytes32(0x487b38c91a22d77f124819ab4d40eea67b11683459c458933cae385630c90816)
        ]
    ];

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            20568177 // 2024-08-19 23:54:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
    }

    function testClaim() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        // Morpho claim rewards is depends on the account input, so even if the wallet is not the one
        // with rewards, wallet can still claim it, but just rewards still goes to the original owner
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            morphoRewardsActionsScripts,
            abi.encodeWithSelector(
                MorphoRewardsActions.claim.selector, distributors[0], accounts[0], rewards[0], claimables[0], proofs[0]
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(0xc55126051B22eBb829D00368f4B12Bde432de5Da).balanceOf(sampleAccount), 0);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(0xc55126051B22eBb829D00368f4B12Bde432de5Da).balanceOf(sampleAccount), 547387349612);
    }

    function testClaimAll() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        // Morpho claim rewards is depends on the account input, so even if the wallet is not the one
        // with rewards, wallet can still claim it, but just rewards still goes to the original owner
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            morphoRewardsActionsScripts,
            abi.encodeWithSelector(
                MorphoRewardsActions.claimAll.selector, distributors, accounts, rewards, claimables, proofs
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(0xc55126051B22eBb829D00368f4B12Bde432de5Da).balanceOf(sampleAccount), 0);
        assertEq(IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7).balanceOf(sampleAccount), 0);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(0xc55126051B22eBb829D00368f4B12Bde432de5Da).balanceOf(sampleAccount), 547387349612);
        assertEq(IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7).balanceOf(sampleAccount), 116);
    }
}
