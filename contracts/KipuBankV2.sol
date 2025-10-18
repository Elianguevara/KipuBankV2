// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ─────────────────────────────────────────────────────────────────────────────
//                          IMPORTS (OpenZeppelin / Chainlink)
// ─────────────────────────────────────────────────────────────────────────────
import {AccessControl} from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
import {IERC20}        from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}     from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal Chainlink Aggregator interface.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80, int256 answer, uint256, uint256, uint80);
}

/**
 * @title KipuBankV2
 * @author Victor Elian Guevara
 * @notice Multi-token vault supporting ETH and ERC-20 tokens with access control and a global bank cap in USD (6 decimals).
 * @dev Implements checks-effects-interactions, custom errors, OpenZeppelin AccessControl,
 *      Chainlink price feeds, decimal conversions, and gas optimizations.
 */
contract KipuBankV2 is AccessControl {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Immutable and Constant Variables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Bank administrator role.
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    /// @notice Virtual address used to represent ETH.
    address public constant NATIVE_TOKEN = address(0);

    /// @notice Target decimals for USD accounting (USDC-style).
    uint8 public constant USD_DECIMALS = 6;

    /// @notice Per-transaction withdrawal threshold for ETH (in wei).
    uint256 public immutable withdrawalThresholdNative;

    /// @notice Maximum global bank capacity expressed in USD-6.
    uint256 public immutable bankCapUsd;

    // ─────────────────────────────────────────────────────────────────────────
    // Storage Variables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Global accounting of the bank in USD-6.
    uint256 public totalUsdLocked;

    /// @notice Deposit counter.
    uint256 public depositCount;

    /// @notice Withdrawal counter.
    uint256 public withdrawalCount;

    // ─────────────────────────────────────────────────────────────────────────
    // Nested Mappings
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice User balances per token.
    /// @dev balances[token][user] → amount of token held in the vault.
    mapping(address => mapping(address => uint256)) private balances;

    /// @notice Price feed registry per token (token => Chainlink Aggregator).
    /// @dev For ETH, use NATIVE_TOKEN as key.
    mapping(address => AggregatorV3Interface) private priceFeeds;

    /// @notice Decimals for ERC-20 tokens.
    /// @dev For ETH, decimals are fixed to 18.
    mapping(address => uint8) private tokenDecimals;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a deposit is made.
    event Deposit(address indexed token, address indexed user, uint256 amountToken, uint256 amountUsd6);

    /// @notice Emitted when a withdrawal is made.
    event Withdrawal(address indexed token, address indexed user, uint256 amountToken, uint256 amountUsd6);

    /// @notice Emitted when a price feed is registered or updated.
    event PriceFeedUpdated(address indexed token, address indexed feed);

    /// @notice Emitted when an ERC-20 token is registered.
    event TokenRegistered(address indexed token, uint8 decimals, address indexed feed);

    // ─────────────────────────────────────────────────────────────────────────
    // Custom Errors
    // ─────────────────────────────────────────────────────────────────────────

    error ZeroAmount();
    error BankCapExceeded(uint256 availableUsd6);
    error InsufficientFunds(uint256 balanceToken);
    error WithdrawalThresholdExceeded(uint256 thresholdWei);
    error TransferFailed(bytes reason);
    error FeedNotSet(address token);
    error InvalidPrice();
    error DecimalsNotSet(address token);
    error Unauthorized();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param _admin Address of the initial bank administrator.
     * @param _withdrawalThresholdWei Withdrawal limit per transaction for ETH (wei).
     * @param _bankCapUsd6 Global deposit capacity of the bank expressed in USD-6.
     * @param _ethUsdFeed Chainlink Aggregator for ETH/USD price feed.
     */
    constructor(
        address _admin,
        uint256 _withdrawalThresholdWei,
        uint256 _bankCapUsd6,
        address _ethUsdFeed
    ) {
        if (_admin == address(0)) revert Unauthorized();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ROLE_ADMIN, _admin);

        withdrawalThresholdNative = _withdrawalThresholdWei;
        bankCapUsd = _bankCapUsd6;

        // Register ETH price feed
        priceFeeds[NATIVE_TOKEN] = AggregatorV3Interface(_ethUsdFeed);
        emit PriceFeedUpdated(NATIVE_TOKEN, _ethUsdFeed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Ensures caller has the admin role.
    modifier onlyBankAdmin() {
        if (!hasRole(ROLE_ADMIN, msg.sender)) revert Unauthorized();
        _;
    }

    /// @notice Validates withdrawal conditions for ETH and ERC-20 tokens.
    modifier validWithdrawal(address _token, uint256 _amount) {
        if (_amount == 0) revert ZeroAmount();

        // Specific threshold for ETH
        if (_token == NATIVE_TOKEN && _amount > withdrawalThresholdNative) {
            revert WithdrawalThresholdExceeded(withdrawalThresholdNative);
        }

        uint256 bal = balances[_token][msg.sender];
        if (_amount > bal) revert InsufficientFunds(bal);
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // External Functions: Administration / Configuration
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Registers a new ERC-20 token with its price feed and decimals.
     * @param _token ERC-20 token address.
     * @param _feed Chainlink Aggregator for token/USD.
     * @param _decimals Token decimals (e.g. USDC=6, DAI=18).
     */
    function registerToken(address _token, address _feed, uint8 _decimals) external onlyBankAdmin {
        if (_token == address(0)) revert Unauthorized();
        tokenDecimals[_token] = _decimals;
        priceFeeds[_token] = AggregatorV3Interface(_feed);

        emit TokenRegistered(_token, _decimals, _feed);
    }

    /**
     * @notice Updates the ETH/USD price feed.
     * @param _feed New Chainlink ETH/USD Aggregator address.
     */
    function updateEthFeed(address _feed) external onlyBankAdmin {
        priceFeeds[NATIVE_TOKEN] = AggregatorV3Interface(_feed);
        emit PriceFeedUpdated(NATIVE_TOKEN, _feed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // External Functions: Deposits
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Deposit ETH into the vault.
     */
    function depositETH() external payable {
        if (msg.value == 0) revert ZeroAmount();

        uint256 usd6 = _amountTokenToUsd6(NATIVE_TOKEN, msg.value);

        uint256 newTotal = totalUsdLocked + usd6;
        if (newTotal > bankCapUsd) revert BankCapExceeded(bankCapUsd - totalUsdLocked);

        unchecked {
            totalUsdLocked = newTotal;
            balances[NATIVE_TOKEN][msg.sender] += msg.value;
            depositCount++;
        }

        emit Deposit(NATIVE_TOKEN, msg.sender, msg.value, usd6);
    }

    /**
     * @notice Deposit ERC-20 tokens into the vault.
     * @param _token Token address.
     * @param _amount Token amount to deposit.
     */
    function depositERC20(address _token, uint256 _amount) external {
        if (_amount == 0) revert ZeroAmount();
        if (priceFeeds[_token] == AggregatorV3Interface(address(0))) revert FeedNotSet(_token);
        if (tokenDecimals[_token] == 0) revert DecimalsNotSet(_token);

        uint256 usd6 = _amountTokenToUsd6(_token, _amount);

        uint256 newTotal = totalUsdLocked + usd6;
        if (newTotal > bankCapUsd) revert BankCapExceeded(bankCapUsd - totalUsdLocked);

        unchecked {
            totalUsdLocked = newTotal;
            balances[_token][msg.sender] += _amount;
            depositCount++;
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_token, msg.sender, _amount, usd6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // External Functions: Withdrawals
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Withdraw ETH from the vault.
     * @param _amount ETH amount in wei.
     */
    function withdrawETH(uint256 _amount) external validWithdrawal(NATIVE_TOKEN, _amount) {
        uint256 usd6 = _amountTokenToUsd6(NATIVE_TOKEN, _amount);

        {
            uint256 prev = balances[NATIVE_TOKEN][msg.sender];
            unchecked {
                balances[NATIVE_TOKEN][msg.sender] = prev - _amount;
                totalUsdLocked -= usd6;
                withdrawalCount++;
            }
        }

        (bool ok, bytes memory data) = msg.sender.call{value: _amount}("");
        if (!ok) revert TransferFailed(data);

        emit Withdrawal(NATIVE_TOKEN, msg.sender, _amount, usd6);
    }

    /**
     * @notice Withdraw ERC-20 tokens from the vault.
     * @param _token ERC-20 token address.
     * @param _amount Token amount to withdraw.
     */
    function withdrawERC20(address _token, uint256 _amount) external validWithdrawal(_token, _amount) {
        if (priceFeeds[_token] == AggregatorV3Interface(address(0))) revert FeedNotSet(_token);
        if (tokenDecimals[_token] == 0) revert DecimalsNotSet(_token);

        uint256 usd6 = _amountTokenToUsd6(_token, _amount);

        {
            uint256 prev = balances[_token][msg.sender];
            unchecked {
                balances[_token][msg.sender] = prev - _amount;
                totalUsdLocked -= usd6;
                withdrawalCount++;
            }
        }

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdrawal(_token, msg.sender, _amount, usd6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // External View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the user balance for a given token.
    function getBalance(address _token, address _user) external view returns (uint256) {
        return balances[_token][_user];
    }

    /// @notice Returns the registered price feed for a token.
    function getFeed(address _token) external view returns (address) {
        return address(priceFeeds[_token]);
    }

    /// @notice Returns the decimals registered for an ERC-20 token.
    function getTokenDecimals(address _token) external view returns (uint8) {
        return tokenDecimals[_token];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private Helper Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Converts a token amount (or ETH) to USD-6 using Chainlink price feeds.
     * Handles both token decimals and feed decimals safely.
     * @param _token Token address (use NATIVE_TOKEN for ETH).
     * @param _amount Token amount.
     * @return usd6 Equivalent value in USD-6 decimals.
     */
    function _amountTokenToUsd6(address _token, uint256 _amount) private view returns (uint256 usd6) {
        AggregatorV3Interface feed = priceFeeds[_token];
        if (address(feed) == address(0)) revert FeedNotSet(_token);

        (, int256 price, , , ) = feed.latestRoundData();
        if (price <= 0) revert InvalidPrice();

        uint8 feedDecimals = feed.decimals();

        uint8 tknDec = _token == NATIVE_TOKEN ? 18 : tokenDecimals[_token];
        if (_token != NATIVE_TOKEN && tknDec == 0) revert DecimalsNotSet(_token);

        // Formula: (amount * price) / 10^(tknDec + feedDec - USD_DECIMALS)
        uint256 num = _amount * uint256(price);

        uint256 denomExp = uint256(tknDec) + uint256(feedDecimals);
        if (denomExp >= USD_DECIMALS) {
            uint256 denom = 10 ** (denomExp - USD_DECIMALS);
            usd6 = num / denom;
        } else {
            uint256 mul = 10 ** (USD_DECIMALS - denomExp);
            usd6 = num * mul;
        }
    }
}

