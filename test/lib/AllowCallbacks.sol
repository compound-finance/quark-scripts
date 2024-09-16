// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "quark-core/src/QuarkScript.sol";
import "quark-core/src/QuarkWallet.sol";

contract AllowCallbacks is QuarkScript {
    function run(address callbackAddress) public {
        bytes32 callbackSlot = QuarkWalletMetadata.CALLBACK_SLOT;
        assembly {
            tstore(callbackSlot, callbackAddress)
        }
    }

    function clear() public {
        clearCallback();
    }
}
