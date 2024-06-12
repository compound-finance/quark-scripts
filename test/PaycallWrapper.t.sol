// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";
import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {CodeJarHelper} from "src/builder/CodeJarHelper.sol";
import {Paycall} from "src/Paycall.sol";
import {PaycallWrapper} from "src/builder/PaycallWrapper.sol";
import {TransferActions} from "src/DeFiScripts.sol";

contract PaycallWrapperTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    CodeJar codeJar;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
        codeJar = QuarkWallet(payable(factory.walletImplementation())).codeJar();
    }

    /* ===== general tests ===== */
    function testSimpleTransferTransferAndWrapForPaycall() public {
        // Create operation for just TransferActions
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(TransferActions).creationCode;
        IQuarkWallet.QuarkOperation memory op = IQuarkWallet.QuarkOperation({
            nonce: wallet.stateManager().nextNonce(address(wallet)),
            scriptAddress: CodeJarHelper.getCodeAddress(1, type(TransferActions).creationCode),
            scriptCalldata: abi.encodeWithSelector(TransferActions.transferERC20Token.selector, USDC, address(this), 10e6),
            scriptSources: scriptSources,
            expiry: 99999999999
        });

        // Wrap with paycall wrapper
        IQuarkWallet.QuarkOperation memory wrappedPaycallOp = PaycallWrapper.wrap(op, 1, 20e6);

        // Check the transfer action is wrapped in a paycall
        assertEq(wrappedPaycallOp.nonce, op.nonce, "nonce is the same");
        assertEq(
            wrappedPaycallOp.scriptAddress,
            CodeJarHelper.getCodeAddress(1, type(Paycall).creationCode),
            "script address is paycall"
        );
        assertEq(wrappedPaycallOp.expiry, 99999999999, "expiry is the same");
        assertEq(
            wrappedPaycallOp.scriptCalldata,
            abi.encodeWithSelector(Paycall.run.selector, op.scriptAddress, op.scriptCalldata, 20e6),
            "calldata is Paycall.run(op.scriptAddress, op.scriptCalldata, 20e6)"
        );
    }
}