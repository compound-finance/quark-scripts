// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

library Math {
    function subtractFlooredAtZero(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }
}
