// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

import {CodeJarHelper} from "./CodeJarHelper.sol";
import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {Paycall} from "../Paycall.sol";

// Helper library to wrap a QuarkOperation from Actions.sol for a Paycall
library PaycallWrapper {
    function wrap(IQuarkWallet.QuarkOperation memory operation, uint256 chainId, uint256 maxPaymentCost)
        internal
        pure
        returns (IQuarkWallet.QuarkOperation memory)
    {
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = type(Paycall).creationCode;

        return IQuarkWallet.QuarkOperation({
            nonce: operation.nonce,
            scriptAddress: CodeJarHelper.getCodeAddress(chainId, type(Paycall).creationCode),
            scriptCalldata: abi.encodeWithSelector(
                Paycall.run.selector, operation.scriptAddress, operation.scriptCalldata, maxPaymentCost
                ),
            scriptSources: scriptSources,
            expiry: operation.expiry
        });
    }
}
