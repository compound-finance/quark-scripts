// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

/**
 * @dev Math-related helper functions for QuarkBuilder
 */
contract QuarkBuilderMath {
    /**
     * @dev Returns Max(a - b, 0)
     */
    function subtractUnsigned(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b < a) {
            return a - b;
        } else {
            return 0;
        }
    }
}
