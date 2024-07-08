// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

interface IStETH {
    function submit(address _referral) external payable returns (uint256);
}
