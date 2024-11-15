// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {CodeJarHelper} from "./CodeJarHelper.sol";
import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Quotecall} from "../Quotecall.sol";
import {PaymentInfo} from "./PaymentInfo.sol";

// Helper library to wrap a QuarkOperation from Actions.sol for a Paycall
library QuotecallWrapper {
    function wrap(
        IQuarkWallet.QuarkOperation memory operation,
        uint256 chainId,
        string memory paymentTokenSymbol,
        uint256 quotedAmount
    ) internal pure returns (IQuarkWallet.QuarkOperation memory) {
        PaymentInfo.PaymentToken memory paymentToken = PaymentInfo.knownToken(paymentTokenSymbol, chainId);
        bytes memory quotecallSource =
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(paymentToken.priceFeed, paymentToken.token));
        bytes[] memory scriptSources = new bytes[](operation.scriptSources.length + 1);
        for (uint256 i = 0; i < operation.scriptSources.length; i++) {
            scriptSources[i] = operation.scriptSources[i];
        }

        scriptSources[operation.scriptSources.length] = quotecallSource;

        return IQuarkWallet.QuarkOperation({
            nonce: operation.nonce,
            isReplayable: operation.isReplayable,
            scriptAddress: CodeJarHelper.getCodeAddress(quotecallSource),
            scriptCalldata: abi.encodeWithSelector(
                Quotecall.run.selector, operation.scriptAddress, operation.scriptCalldata, quotedAmount
            ),
            scriptSources: scriptSources,
            expiry: operation.expiry
        });
    }
}
