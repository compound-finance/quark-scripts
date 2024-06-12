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
import {Ethcall} from "src/Ethcall.sol";
import {Multicall} from "src/Multicall.sol";
import {Paycall} from "src/Paycall.sol";

import {Counter} from "./lib/Counter.sol";

import {YulHelper} from "./lib/YulHelper.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";
import "src/vendor/chainlink/AggregatorV3Interface.sol";

import "src/DeFiScripts.sol";
import {PaycallWrapper} from "src/builder/PaycallWrapper.sol";

contract PaycallWrapperTest is Test {
    QuarkWalletProxyFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    CodeJar codeJar;

    // Comet address in mainnet
    address constant cUSDCv3 = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant cWETHv3 = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // Mainnet ETH / USD pricefeed
    address constant ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant ETH_BTC_PRICE_FEED = 0xAc559F25B1619171CbC396a50854A3240b6A4e99;

    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    bytes multicall = new YulHelper().getCode("Multicall.sol/Multicall.json");
    bytes ethcall = new YulHelper().getCode("Ethcall.sol/Ethcall.json");
    bytes transferScript = new YulHelper().getCode("DeFiScripts.sol/TransferActions.json");

    // Paycall has its contructor with 2 parameters
    bytes paycall;

    address ethcallAddress;
    address multicallAddress;
    address paycallAddress;
    address transferActionsAddress;
    address paycallUSDTAddress;
    address paycallWBTCAddress;

    function setUp() public {
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
        counter = new Counter();
        counter.setNumber(0);

        codeJar = QuarkWallet(payable(factory.walletImplementation())).codeJar();
        
        ethcallAddress = codeJar.saveCode(ethcall);
        multicallAddress = codeJar.saveCode(multicall);
        transferActionsAddress = codeJar.saveCode(transferScript);
        paycall = abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_USD_PRICE_FEED, USDC));
        paycallAddress = codeJar.saveCode(paycall);
    }

    /* ===== general tests ===== */
    function testSimpleTransferTransferAndWrapForPaycall() public {
        // Create operation for just TransferActions
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(TransferActions).creationCode;
        IQuarkWallet.QuarkOperation memory op = IQuarkWallet.QuarkOperation({
            nonce: wallet.stateManager().nextNonce(address(wallet)),
            scriptAddress: transferActionsAddress,
            scriptCalldata: abi.encodeWithSelector(
                TransferActions.transferERC20Token.selector,
                USDC,
                address(this),
                10e6
            ),
            scriptSources: scriptSources,
            expiry: 99999999999
        });

        // Wrap with paycall wrapper
        IQuarkWallet.QuarkOperation memory wrappedPaycallOp = PaycallWrapper.wrap(op, 1, 20e6);

        // Check the transfer action is wrapped in a paycall
        assertEq(wrappedPaycallOp.nonce, op.nonce, "nonce is the same");
        assertEq(wrappedPaycallOp.scriptAddress, paycallAddress, "script address is paycall");
        assertEq(wrappedPaycallOp.expiry, 99999999999, "expiry is the same");
        assertEq(wrappedPaycallOp.scriptCalldata, abi.encodeWithSelector(
            Paycall.run.selector,
            op.scriptAddress,
            op.scriptCalldata,
            20e6
        ), "calldata is Paycall.run(op.scriptAddress, op.scriptCalldata, 20e6)");

    }
}
