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

    function wrapAllETH(address weth) external payable {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            IWETH(weth).deposit{value: ethBalance}();
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

    function unwrapAllWETH(address weth) external payable {
        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        if (wethBalance > 0) {
            IWETH(weth).withdraw(wethBalance);
        }
    }

    function wrapLidoStETH(address wstETH, address stETH, uint256 amount) external {
        IERC20(stETH).approve(wstETH, amount);
        IWstETH(wstETH).wrap(amount);
    }

    function wrapAllLidoStETH(address wstETH, address stETH) external payable {
        uint256 stETHBalance = IERC20(stETH).balanceOf(address(this));
        if (stETHBalance > 0) {
            IERC20(stETH).approve(wstETH, stETHBalance);
            IWstETH(wstETH).wrap(stETHBalance);
        }
    }

    function unwrapLidoWstETH(address wstETH, uint256 amount) external {
        IWstETH(wstETH).unwrap(amount);
    }

    function unwrapAllLidoWstETH(address wstETH) external {
        uint256 wstETHBalance = IERC20(wstETH).balanceOf(address(this));
        if (wstETHBalance > 0) {
            IWstETH(wstETH).unwrap(wstETHBalance);
        }
    }
}
