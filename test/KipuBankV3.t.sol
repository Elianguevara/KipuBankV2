// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {KipuBankV3} from "../src/KipuBankV3.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockWETH} from "./mocks/MockWETH.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockRouter} from "./mocks/MockRouter.sol";

contract KipuBankV3Test is Test {
    KipuBankV3 private bank;
    MockUSDC private usdc;
    MockWETH private weth;
    MockRouter private router;
    MockERC20 private tokenA;

    address private constant ADMIN = address(0xA11CE);
    address private constant USER = address(0xBEEF);

    uint256 private constant BANK_CAP = 10_000_000e6; // 10M USDC
    uint256 private constant WITHDRAW_LIMIT = 1_000_000e6; // 1M USDC

    function setUp() public {
        usdc = new MockUSDC();
        weth = new MockWETH();
        router = new MockRouter(address(weth), usdc);
        tokenA = new MockERC20("Token A", "TKA", 18);

        bank = new KipuBankV3(ADMIN, address(usdc), address(router), BANK_CAP, WITHDRAW_LIMIT);

        // Provide liquidity to router for swaps
        usdc.mint(address(router), 5_000_000e6);
        vm.deal(address(router), 100 ether);
        vm.deal(USER, 100 ether);

        // Configure simple rates
        // 1 ETH -> 2,000 USDC
        router.setRate(address(weth), address(usdc), 2_000_000_000000, 1e18); // 2,000 * 1e6
        // 1 USDC -> 0.0005 ETH (5e14 wei)
        router.setRate(address(usdc), address(weth), 5e14, 1e6);
        // 1 tokenA -> 2 USDC
        router.setRate(address(tokenA), address(usdc), 2_000_000, 1e18);
    }

    function testDepositUSDC() public {
        uint256 amount = 1_000_000e6;
        usdc.mint(USER, amount);

        vm.prank(USER);
        usdc.approve(address(bank), amount);

        vm.prank(USER);
        bank.depositUSDC(amount);

        assertEq(bank.s_totalUSD6(), amount);
        assertEq(bank.getBalanceUSD6(USER, address(usdc)), amount);
        assertEq(usdc.balanceOf(address(bank)), amount);
    }

    function testDepositTokenSwapsToUSDC() public {
        uint256 tokenAmount = 5 ether;
        tokenA.mint(USER, tokenAmount);

        uint256 expectedUSDC = (tokenAmount * 2_000_000) / 1e18; // 10 USDC

        vm.prank(USER);
        tokenA.approve(address(bank), tokenAmount);

        vm.prank(USER);
        bank.depositToken(address(tokenA), tokenAmount, expectedUSDC, _deadline());

        assertEq(bank.getBalanceUSD6(USER, address(usdc)), expectedUSDC);
        assertEq(bank.s_totalUSD6(), expectedUSDC);
        assertEq(usdc.balanceOf(address(bank)), expectedUSDC);
        assertEq(tokenA.balanceOf(address(router)), tokenAmount);
    }

    function testDepositETHSwapsToUSDC() public {
        uint256 ethAmount = 1 ether;
        uint256 expectedUSDC = (ethAmount * 2_000_000_000000) / 1e18; // 2,000 USDC

        vm.prank(USER);
        bank.depositETH{value: ethAmount}(expectedUSDC, _deadline());

        assertEq(bank.getBalanceUSD6(USER, address(usdc)), expectedUSDC);
        assertEq(bank.s_totalUSD6(), expectedUSDC);
        assertEq(address(bank).balance, 0); // ETH routed through swap
    }

    function testBankCapIsEnforced() public {
        uint256 initial = BANK_CAP - 5_000_000; // leave 5 USDC of headroom
        usdc.mint(USER, initial + 1_000_000e6);
        tokenA.mint(USER, 10 ether);

        vm.startPrank(USER);
        usdc.approve(address(bank), type(uint256).max);
        bank.depositUSDC(initial);

        tokenA.approve(address(bank), type(uint256).max);
        vm.expectRevert(KipuBankV3.KBV3_CapExceeded.selector);
        bank.depositToken(address(tokenA), 10 ether, 0, _deadline());
        vm.stopPrank();
    }

    function testWithdrawUSDC() public {
        uint256 amount = 500_000e6;
        usdc.mint(USER, amount);

        vm.startPrank(USER);
        usdc.approve(address(bank), amount);
        bank.depositUSDC(amount);

        bank.withdrawUSDC(200_000e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(USER), 200_000e6);
        assertEq(bank.getBalanceUSD6(USER, address(usdc)), 300_000e6);
        assertEq(bank.s_totalUSD6(), 300_000e6);
    }

    function testWithdrawETHSwapsFromUSDC() public {
        uint256 amount = 40_000e6;
        usdc.mint(USER, amount);

        vm.startPrank(USER);
        usdc.approve(address(bank), amount);
        bank.depositUSDC(amount);

        uint256 withdrawAmount = 20_000e6;
        uint256 expectedEth = (withdrawAmount * 5e14) / 1e6; // based on router rate
        uint256 userEthBefore = USER.balance;

        bank.withdrawETH(withdrawAmount, expectedEth, _deadline());
        vm.stopPrank();

        assertEq(USER.balance, userEthBefore + expectedEth);
        assertEq(bank.getBalanceUSD6(USER, address(usdc)), amount - withdrawAmount);
        assertEq(bank.s_totalUSD6(), amount - withdrawAmount);
    }

    function testPauseBlocksDeposits() public {
        vm.prank(ADMIN);
        bank.pause();

        usdc.mint(USER, 100_000e6);
        vm.prank(USER);
        usdc.approve(address(bank), 100_000e6);

        vm.prank(USER);
        vm.expectRevert("Pausable: paused");
        bank.depositUSDC(100_000e6);
    }

    function _deadline() private view returns (uint256) {
        return block.timestamp + 1 hours;
    }
}
