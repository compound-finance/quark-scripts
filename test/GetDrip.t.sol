// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/GetDrip.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {CodeJar} from "codejar/src/CodeJar.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {YulHelper} from "./lib/YulHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";

/**
 * Tests approve and execute against 0x
 */
contract GetDripTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11cee;
    address alice = vm.addr(alicePrivateKey);
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant fauceteer = 0x68793eA49297eB75DFB4610B68e076D2A5c7646C;

    function setUp() public {
        // Fork setup
        vm.createSelectFork("https://sepolia.infura.io/v3/531e3eb124194de5a88caec726d10bea");
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
    }

    // Tests dripping some usdc
    function testDrip() public {
        vm.pauseGasMetering();

        QuarkWallet wallet = QuarkWallet(factory.create(alice, alice));
        new YulHelper().deploy("GetDrip.sol/GetDrip.json");

        bytes memory getDripScript = new YulHelper().getCode("GetDrip.sol/GetDrip.json");

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet, getDripScript, abi.encodeCall(GetDrip.drip, (fauceteer, USDC)), ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0);
        wallet.executeQuarkOperation(op, signature);

        // The drip always gives this amount
        assertNotEq(IERC20(USDC).balanceOf(address(wallet)), 0);
    }
}
