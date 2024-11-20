// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";

contract WrapperActions {
    function wrapETH(address weth, uint256 amount) external payable {
        IWETH(weth).deposit{value: amount}();
    }

    function wrapETHUpTo(address weth, uint256 targetAmount) external payable {
        uint256 currentBalance = IERC20(weth).balanceOf(address(this));
        if (currentBalance < targetAmount) {
            IWETH(weth).deposit{value: targetAmount - currentBalance}();
        }
    }

    function unwrapWETH(address weth, uint256 amount) external {
        IWETH(weth).withdraw(amount);
    }

    function unwrapWETHUpTo(address weth, uint256 targetAmount) external {
        uint256 currentBalance = address(this).balance;
        if (currentBalance < targetAmount) {
            IWETH(weth).withdraw(targetAmount - currentBalance);
        }
    }

    function wrapLidoStETH(address wstETH, address stETH, uint256 amount) external {
        IERC20(stETH).approve(wstETH, amount);
        IWstETH(wstETH).wrap(amount);
    }

    function unwrapLidoWstETH(address wstETH, uint256 amount) external {
        IWstETH(wstETH).unwrap(amount);
    }
}
