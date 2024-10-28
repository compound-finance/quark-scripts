// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {CometActionsBuilder} from "src/builder/actions/CometActionsBuilder.sol";
import {MorphoVaultActionsBuilder} from "src/builder/actions/MorphoVaultActionsBuilder.sol";
import {MorphoActionsBuilder} from "src/builder/actions/MorphoActionsBuilder.sol";
import {SwapActionsBuilder} from "src/builder/actions/SwapActionsBuilder.sol";
import {TransferActionsBuilder} from "src/builder/actions/TransferActionsBuilder.sol";

contract QuarkBuilder is
    CometActionsBuilder,
    MorphoVaultActionsBuilder,
    MorphoActionsBuilder,
    SwapActionsBuilder,
    TransferActionsBuilder
{
// This contract is a composite of the various scripts that can be used to build a Quark operation
// It is a convenience for developers to have all the scripts in one place
}
