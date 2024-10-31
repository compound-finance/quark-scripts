// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {Actions} from "src/builder/actions/Actions.sol";
import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {QuarkBuilderBase} from "src/builder/QuarkBuilderBase.sol";

/// @dev Interface for foreign function interface (FFI) contracts
interface IFFI {
    function simulate(IQuarkWallet.QuarkOperation[] memory quarkOperations, Actions.Action[] memory actionsArray)
        external
        pure
        returns (QuarkBuilderBase.Simulation[] memory);
}
