// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {CodeJarHelper} from "./CodeJarHelper.sol";
import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Quotecall} from "../Quotecall.sol";

// Helper library to wrap a QuarkOperation from Actions.sol for a Paycall
library QuotecallWrapper {
    function wrap(IQuarkWallet.QuarkOperation memory operation, uint256 chainId, uint256 quotedAmount)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory)
    {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(Quotecall).creationCode;

        return IQuarkWallet.QuarkOperation({
            nonce: operation.nonce,
            scriptAddress: CodeJarHelper.getCodeAddress(chainId, type(Quotecall).creationCode),
            scriptCalldata: abi.encodeWithSelector(
                Quotecall.run.selector, operation.scriptAddress, operation.scriptCalldata, quotedAmount
            ),
            scriptSources: scriptSources,
            expiry: operation.expiry
        });
    }
}
