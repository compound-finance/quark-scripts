// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {CodeJarHelper} from "./CodeJarHelper.sol";
import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Quotecall} from "../Quotecall.sol";
import {PaymentTokens} from "./PaymentTokens.sol";

// Helper library to wrap a QuarkOperation from Actions.sol for a Paycall
library QuotecallWrapper {
    function wrap(IQuarkWallet.QuarkOperation memory operation, uint256 chainId, uint256 quotedAmount)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory)
    {
        PaymentTokens.PaymentToken memory paymentToken = PaymentTokens.knownToken(chainId);
        bytes memory quotecallSource =
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(paymentToken.priceFeed, paymentToken.token));
        bytes[] memory scriptSources = new bytes[](operation.scriptSources.length + 1);
        for (uint256 i = 0; i < operation.scriptSources.length; i++) {
            scriptSources[i] = operation.scriptSources[i];
        }

        scriptSources[operation.scriptSources.length] = quotecallSource;

        return IQuarkWallet.QuarkOperation({
            nonce: operation.nonce,
            scriptAddress: CodeJarHelper.getCodeAddress(chainId, quotecallSource),
            scriptCalldata: abi.encodeWithSelector(
                Quotecall.run.selector, operation.scriptAddress, operation.scriptCalldata, quotedAmount
                ),
            scriptSources: scriptSources,
            expiry: operation.expiry
        });
    }
}
