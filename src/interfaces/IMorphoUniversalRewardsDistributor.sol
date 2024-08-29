// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

/// @dev Interface for Morpho Universal Rewards Distributor
/// Reference: https://github.com/morpho-org/universal-rewards-distributor/blob/main/src/UniversalRewardsDistributor.sol
interface IMorphoUniversalRewardsDistributor {
    function claim(address account, address reward, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount);
}
