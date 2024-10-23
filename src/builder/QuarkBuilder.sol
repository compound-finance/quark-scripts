// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {CometBuilderScripts} from "src/builder/scripts/CometBuilderScripts.sol";
import {MorphoVaultBuilderScripts} from "src/builder/scripts/MorphoVaultBuilderScripts.sol";
import {MorphoBuilderScripts} from "src/builder/scripts/MorphoBuilderScripts.sol";
import {SwapBuilderScripts} from "src/builder/scripts/SwapBuilderScripts.sol";
import {TransferBuilderScripts} from "src/builder/scripts/TransferBuilderScripts.sol";

contract QuarkBuilder is
    CometBuilderScripts,
    MorphoVaultBuilderScripts,
    MorphoBuilderScripts,
    SwapBuilderScripts,
    TransferBuilderScripts
{
// This contract is a composite of the various scripts that can be used to build a Quark operation
// It is a convenience for developers to have all the scripts in one place
// It is not meant to be deployed or used as a standalone contract
// It is meant to be used as a library for other contracts that need to build Quark operations
}
