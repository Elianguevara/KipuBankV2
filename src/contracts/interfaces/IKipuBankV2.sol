// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IKipuBankV2
 * @notice Interface for KipuBankV2 contract exposing its external functions.
 * @dev Use this interface to interact with KipuBankV2 from other contracts.
 */
interface IKipuBankV2 {
    // ─────────────────────────────────────────────────────────────────────────
    // User Actions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Deposits ETH into the bank.
     */
    function depositETH() external payable;

    /**
     * @notice Deposits ERC-20 tokens into the bank.
     * @param _token Address of the ERC-20 token.
     * @param _amount Amount to deposit (in token's decimals).
     */
    function depositERC20(address _token, uint256 _amount) external;

    /**
     * @notice Withdraws ETH from the bank.
     * @param _amount Amount to withdraw (in wei).
     */
    function withdrawETH(uint256 _amount) external;

    /**
     * @notice Withdraws ERC-20 tokens from the bank.
     * @param _token Address of the ERC-20 token.
     * @param _amount Amount to withdraw (in token's decimals).
     */
    function withdrawERC20(address _token, uint256 _amount) external;

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the balance of a token for a user.
     * @param _token Token address (address(0) for ETH).
     * @param _user User address.
     * @return Balance in token units.
     */
    function getBalance(address _token, address _user) external view returns (uint256);

    /**
     * @notice Returns the price feed address for a token.
     * @param _token Token address.
     * @return Price feed address.
     */
    function getFeed(address _token) external view returns (address);

    /**
     * @notice Returns the decimals for a token.
     * @param _token Token address.
     * @return Number of decimals.
     */
    function getTokenDecimals(address _token) external view returns (uint8);

    // ─────────────────────────────────────────────────────────────────────────
    // Admin Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Registers a new ERC-20 token with price feed.
     * @param _token Token address.
     * @param _feed Chainlink feed address.
     * @param _decimals Token decimals.
     */
    function registerToken(address _token, address _feed, uint8 _decimals) external;

    /**
     * @notice Updates the ETH price feed.
     * @param _feed New price feed address.
     */
    function updateEthFeed(address _feed) external;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants & Immutables (for reference)
    // ─────────────────────────────────────────────────────────────────────────

    function NATIVE_TOKEN() external view returns (address);
    function USD_DECIMALS() external view returns (uint8);
    function withdrawalThresholdNative() external view returns (uint256);
    function bankCapUsd() external view returns (uint256);
    function totalUsdLocked() external view returns (uint256);
    function depositCount() external view returns (uint256);
    function withdrawalCount() external view returns (uint256);
}