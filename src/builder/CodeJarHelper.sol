// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

library CodeJarHelper {
    function knownCodeJar(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) {
            return address(0xff); // FIXME
        } else if (chainId == 8453) {
            return address(0xfff); // FIXME
        } else {
            revert(); // FIXME
        }
    }

    function getCodeAddress(uint256 chainId, bytes memory code) public pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), knownCodeJar(chainId), uint256(0), keccak256(code)))))
        );
    }
}
