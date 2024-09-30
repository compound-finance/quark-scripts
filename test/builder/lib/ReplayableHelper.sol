// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

library ReplayableHelper {
    function generateNonceFromSecret(bytes32 secret, uint256 totalPlays) internal pure returns (bytes32) {
        uint256 replayCount = totalPlays - 1;
        for (uint256 i = 0; i < replayCount; ++i) {
            secret = keccak256(abi.encodePacked(secret));
        }
        return secret;
    }
}
