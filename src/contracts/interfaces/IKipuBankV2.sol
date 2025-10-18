// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IKipuBankV2
 * @notice Interface for KipuBankV2 contract exposing its external functions.
 */
interface IKipuBankV2 {
    // --- User Actions ---
    function depositETH() external payable;
    function depositERC20(address _token, uint256 _amount) external;
    function withdrawETH(uint256 _amount) external;
    function withdrawERC20(address _token, uint256 _amount) external;

    // --- View Functions ---
    function getBalance(address _token, address _user) external view returns (uint256);
    function getFeed(address _token) external view returns (address);
    function getTokenDecimals(address _token) external view returns (uint8);

    // --- Admin Functions ---
    function registerToken(address _token, address _feed, uint8 _decimals) external;
    function updateEthFeed(address _feed) external;
}


