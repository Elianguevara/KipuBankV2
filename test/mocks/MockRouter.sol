// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockERC20} from "./MockERC20.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";

contract MockRouter is IUniswapV2Router02 {
    struct Rate {
        uint256 numerator;
        uint256 denominator;
    }

    address public immutable weth;
    MockUSDC public immutable usdc;

    mapping(bytes32 => Rate) private s_rates;

    constructor(address weth_, MockUSDC usdc_) {
        weth = weth_;
        usdc = usdc_;
    }

    receive() external payable {}

    function setRate(address tokenIn, address tokenOut, uint256 numerator, uint256 denominator) external {
        require(denominator != 0, "MockRouter: denominator");
        s_rates[_rateKey(tokenIn, tokenOut)] = Rate({numerator: numerator, denominator: denominator});
    }

    function WETH() external view override returns (address) {
        return weth;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        require(path.length == 2, "MockRouter: path");
        Rate memory rate = s_rates[_rateKey(path[0], path[1])];
        require(rate.denominator != 0, "MockRouter: rate");
        uint256 amountOut = (amountIn * rate.numerator) / rate.denominator;
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "MockRouter: deadline");
        require(path.length == 2 && path[0] == weth, "MockRouter: path");
        Rate memory rate = s_rates[_rateKey(path[0], path[1])];
        require(rate.denominator != 0, "MockRouter: rate");
        uint256 amountOut = (msg.value * rate.numerator) / rate.denominator;
        require(amountOut >= amountOutMin, "MockRouter: slippage");
        usdc.transfer(to, amountOut);
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = amountOut;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "MockRouter: deadline");
        require(path.length == 2, "MockRouter: path");
        Rate memory rate = s_rates[_rateKey(path[0], path[1])];
        require(rate.denominator != 0, "MockRouter: rate");
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = (amountIn * rate.numerator) / rate.denominator;
        require(amountOut >= amountOutMin, "MockRouter: slippage");
        if (path[1] == address(usdc)) {
            usdc.transfer(to, amountOut);
        } else {
            MockERC20(path[1]).transfer(to, amountOut);
        }
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "MockRouter: deadline");
        require(path.length == 2 && path[1] == weth, "MockRouter: path");
        Rate memory rate = s_rates[_rateKey(path[0], path[1])];
        require(rate.denominator != 0, "MockRouter: rate");
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = (amountIn * rate.numerator) / rate.denominator;
        require(amountOut >= amountOutMin, "MockRouter: slippage");
        (bool ok, ) = payable(to).call{value: amountOut}("");
        require(ok, "MockRouter: eth");
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function _rateKey(address tokenIn, address tokenOut) private pure returns (bytes32) {
        return keccak256(abi.encode(tokenIn, tokenOut));
    }
}
