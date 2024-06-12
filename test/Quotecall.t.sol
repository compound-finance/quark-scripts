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
import {Quotecall} from "src/Quotecall.sol";
import {QuotecallWrapper} from "src/builder/QuotecallWrapper.sol";
import {TransferActions} from "src/DeFiScripts.sol";

contract QuotecallWrapperTest is Test {
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
    function testSimpleTransferTransferAndWrapForQuotecall() public {
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

        // Wrap with Quotecall wrapper
        IQuarkWallet.QuarkOperation memory wrappedQuotecallOp = QuotecallWrapper.wrap(op, 1, 20e6);

        // Check the transfer action is wrapped in a Quotecall
        assertEq(wrappedQuotecallOp.nonce, op.nonce, "nonce should be the same");
        assertEq(
            wrappedQuotecallOp.scriptAddress,
            CodeJarHelper.getCodeAddress(1, type(Quotecall).creationCode),
            "script address should be Quotecall"
        );
        assertEq(wrappedQuotecallOp.expiry, 99999999999, "expiry should be the same");
        assertEq(
            wrappedQuotecallOp.scriptCalldata,
            abi.encodeWithSelector(Quotecall.run.selector, op.scriptAddress, op.scriptCalldata, 20e6),
            "calldata should be Quotecall.run(op.scriptAddress, op.scriptCalldata, 20e6)"
        );
    }
}
