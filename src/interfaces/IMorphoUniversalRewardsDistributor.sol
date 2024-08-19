// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

interface IMorphoUniversalRewardsDistributor {
    function claim(address account, address reward, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount);
}
