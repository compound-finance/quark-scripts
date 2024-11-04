// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

/// Library of shared errors used across Quark Builder files
library Errors {
    error BadData();
    error NoKnownBridge(string bridgeType, uint256 srcChainId);
}
