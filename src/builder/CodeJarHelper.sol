// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

library CodeJarHelper {
    /* ===== Constants ===== */

    /// @notice The address for CodeJar on all chains
    address constant CODE_JAR_ADDRESS = 0x2b68764bCfE9fCD8d5a30a281F141f69b69Ae3C8;

    function getCodeAddress(bytes memory code) internal pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CODE_JAR_ADDRESS, uint256(0), keccak256(code)))))
        );
    }
}
