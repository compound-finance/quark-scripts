// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";

/// @dev Interface for MetaMorpho (vault) for earn
/// Reference: https://github.com/morpho-org/metamorpho/blob/main/src/MetaMorpho.sol
interface IMetaMorpho is IERC4626 {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}
