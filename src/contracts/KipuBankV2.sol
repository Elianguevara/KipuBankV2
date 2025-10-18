// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ─────────────────────────────────────────────────────────────────────────────
//                          IMPORTS (OpenZeppelin / Chainlink)
// ─────────────────────────────────────────────────────────────────────────────
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20}        from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregatorV3Interface} from "./interfaces/IAggregatorV3Interface.sol"; // separada

/**
 * @title KipuBankV2
 * @author Victor Elian Guevara
 * @notice Multi-token vault supporting ETH and ERC-20 with access control and global bank cap in USD (6 decimals).
 * @dev Implements CEI pattern, custom errors, AccessControl, Chainlink feeds, safe transfers and gas-optimized storage.
 */
contract KipuBankV2 is AccessControl {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants & Immutables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Bank administrator role.
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    /// @notice Virtual address used to represent ETH deposits.
    address public constant NATIVE_TOKEN = address(0);

    /// @notice Target decimals for USD accounting (USDC-style).
    uint8 public constant USD_DECIMALS = 6;

    /// @notice Per-transaction withdrawal threshold for ETH (wei).
    uint256 public immutable withdrawalThresholdNative;

    /// @notice Global capacity limit expressed in USD-6.
    uint256 public immutable bankCapUsd;

    // ─────────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Global accounting of locked value (USD-6).
    uint256 public totalUsdLocked;

    uint256 public depositCount;
    uint256 public withdrawalCount;

    /// @notice Balances[token][user] → amount in token units.
    mapping(address => mapping(address => uint256)) private balances;

    /// @notice Price feed registry.
    mapping(address => IAggregatorV3Interface) private priceFeeds;

    /// @notice Registered decimals for ERC-20 tokens (ETH = assumed 18).
    mapping(address => uint8) private tokenDecimals;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event Deposit(address indexed token, address indexed user, uint256 amountToken, uint256 amountUsd6);
    event Withdrawal(address indexed token, address indexed user, uint256 amountToken, uint256 amountUsd6);
    event PriceFeedUpdated(address indexed token, address indexed feed);
    event TokenRegistered(address indexed token, uint8 decimals, address indexed feed);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
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

        // Register ETH feed
        priceFeeds[NATIVE_TOKEN] = IAggregatorV3Interface(_ethUsdFeed);
        emit PriceFeedUpdated(NATIVE_TOKEN, _ethUsdFeed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyBankAdmin() {
        if (!hasRole(ROLE_ADMIN, msg.sender)) revert Unauthorized();
        _;
    }

    modifier validWithdrawal(address _token, uint256 _amount) {
        if (_amount == 0) revert ZeroAmount();
        if (_token == NATIVE_TOKEN && _amount > withdrawalThresholdNative) {
            revert WithdrawalThresholdExceeded(withdrawalThresholdNative);
        }
        uint256 bal = balances[_token][msg.sender];
        if (_amount > bal) revert InsufficientFunds(bal);
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin Functions
    // ─────────────────────────────────────────────────────────────────────────

    function registerToken(address _token, address _feed, uint8 _decimals) external onlyBankAdmin {
        if (_token == address(0)) revert Unauthorized();
        tokenDecimals[_token] = _decimals;
        priceFeeds[_token] = IAggregatorV3Interface(_feed);
        emit TokenRegistered(_token, _decimals, _feed);
    }

    function updateEthFeed(address _feed) external onlyBankAdmin {
        priceFeeds[NATIVE_TOKEN] = IAggregatorV3Interface(_feed);
        emit PriceFeedUpdated(NATIVE_TOKEN, _feed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deposits
    // ─────────────────────────────────────────────────────────────────────────

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

    function depositERC20(address _token, uint256 _amount) external {
        if (_amount == 0) revert ZeroAmount();
        if (address(priceFeeds[_token]) == address(0)) revert FeedNotSet(_token);
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
    // Withdrawals
    // ─────────────────────────────────────────────────────────────────────────

    function withdrawETH(uint256 _amount) external validWithdrawal(NATIVE_TOKEN, _amount) {
        uint256 usd6 = _amountTokenToUsd6(NATIVE_TOKEN, _amount);
        unchecked {
            balances[NATIVE_TOKEN][msg.sender] -= _amount;
            totalUsdLocked -= usd6;
            withdrawalCount++;
        }
        (bool ok, bytes memory data) = msg.sender.call{value: _amount}("");
        if (!ok) revert TransferFailed(data);

        emit Withdrawal(NATIVE_TOKEN, msg.sender, _amount, usd6);
    }

    function withdrawERC20(address _token, uint256 _amount) external validWithdrawal(_token, _amount) {
        if (address(priceFeeds[_token]) == address(0)) revert FeedNotSet(_token);
        if (tokenDecimals[_token] == 0) revert DecimalsNotSet(_token);

        uint256 usd6 = _amountTokenToUsd6(_token, _amount);
        unchecked {
            balances[_token][msg.sender] -= _amount;
            totalUsdLocked -= usd6;
            withdrawalCount++;
        }

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdrawal(_token, msg.sender, _amount, usd6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    function getBalance(address _token, address _user) external view returns (uint256) {
        return balances[_token][_user];
    }

    function getFeed(address _token) external view returns (address) {
        return address(priceFeeds[_token]);
    }

    function getTokenDecimals(address _token) external view returns (uint8) {
        return tokenDecimals[_token];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _amountTokenToUsd6(address _token, uint256 _amount) private view returns (uint256 usd6) {
        IAggregatorV3Interface feed = priceFeeds[_token];
        if (address(feed) == address(0)) revert FeedNotSet(_token);

        (, int256 price, , , ) = feed.latestRoundData();
        if (price <= 0) revert InvalidPrice();

        uint8 feedDecimals = feed.decimals();
        uint8 tknDec = _token == NATIVE_TOKEN ? 18 : tokenDecimals[_token];
        if (_token != NATIVE_TOKEN && tknDec == 0) revert DecimalsNotSet(_token);

        uint256 num = _amount * uint256(price);
        uint256 denomExp = uint256(tknDec) + uint256(feedDecimals);

        if (denomExp >= USD_DECIMALS) {
            usd6 = num / (10 ** (denomExp - USD_DECIMALS));
        } else {
            usd6 = num * (10 ** (USD_DECIMALS - denomExp));
        }
    }
}
