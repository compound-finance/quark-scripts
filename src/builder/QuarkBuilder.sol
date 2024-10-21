// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {Comet} from "src/builder/scripts/Comet.sol";
import {Morpho} from "src/builder/scripts/Morpho.sol";
import {MorphoVault} from "src/builder/scripts/MorphoVault.sol";
import {Swap} from "src/builder/scripts/Swap.sol";
import {Transfer} from "src/builder/scripts/Transfer.sol";
import {RecurringSwap} from "src/builder/scripts/RecurringSwap.sol";

contract QuarkBuilder is Comet, Morpho, MorphoVault, Swap, Transfer, RecurringSwap {
// This contract is a placeholder for the QuarkBuilder library
// It is used to deploy the library to the blockchain
// The library is then linked to the QuarkWallet contract
// This contract is never deployed or interacted with directly
// It is only used to deploy the library to the blockchain
}
