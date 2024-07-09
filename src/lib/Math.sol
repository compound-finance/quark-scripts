// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

library Math {
    function substractOrZero(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }
}
