// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

interface IWstETH {
    function wrap(uint256 amount) external returns (uint256);
    function unwrap(uint256 amount) external returns (uint256);
}
