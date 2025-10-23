// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ─────────────────────────────────────────────────────────────────────────────
//                          IMPORTS (OpenZeppelin)
// ─────────────────────────────────────────────────────────────────────────────
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20}        from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregatorV3Interface} from "./interfaces/IAggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 * @author Victor Elian Guevara
 * @notice Multi-token vault supporting ETH and ERC-20 with access control and global bank cap in USD (6 decimals).
 * @dev Implements CEI pattern, custom errors, AccessControl, Chainlink feeds, safe transfers and gas-optimized storage.
 */
contract KipuBankV2 is AccessControl {
    using SafeERC20 for IERC20;

    // ═════════════════════════════════════════════════════════════════════════
    // 1. CONTROL DE ACCESO
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Bank administrator role.
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    // ═════════════════════════════════════════════════════════════════════════
    // 2. DECLARACIONES DE TIPOS (Custom Errors & Events)
    // ═════════════════════════════════════════════════════════════════════════

    // ─────────────────────────────────────────────────────────────────────────
    // Custom Errors
    // ─────────────────────────────────────────────────────────────────────────

    error ZeroAmount();
    error ZeroAddress();
    error BankCapExceeded(uint256 availableUsd6);
    error InsufficientFunds(uint256 balanceToken);
    error WithdrawalThresholdExceeded(uint256 thresholdWei);
    error TransferFailed(bytes reason);
    error FeedNotSet(address token);
    error InvalidPrice();
    error DecimalsNotSet(address token);
    error Unauthorized();

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event Deposit(address indexed token, address indexed user, uint256 amountToken, uint256 amountUsd6);
    event Withdrawal(address indexed token, address indexed user, uint256 amountToken, uint256 amountUsd6);
    event PriceFeedUpdated(address indexed token, address indexed feed);
    event TokenRegistered(address indexed token, uint8 decimals, address indexed feed);

    // ═════════════════════════════════════════════════════════════════════════
    // 3. INSTANCIA DEL ORÁCULO CHAINLINK (Price Feed Registry)
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Price feed registry mapping token address to Chainlink aggregator.
    mapping(address => IAggregatorV3Interface) private priceFeeds;

    // ═════════════════════════════════════════════════════════════════════════
    // 4. VARIABLES CONSTANT & IMMUTABLE
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Virtual address used to represent ETH deposits.
    address public constant NATIVE_TOKEN = address(0);

    /// @notice Target decimals for USD accounting (USDC-style).
    uint8 public constant USD_DECIMALS = 6;

    /// @notice Per-transaction withdrawal threshold for ETH (wei).
    uint256 public immutable withdrawalThresholdNative;

    /// @notice Global capacity limit expressed in USD-6.
    uint256 public immutable bankCapUsd;

    // ═════════════════════════════════════════════════════════════════════════
    // 5. MAPPINGS (Estado del contrato)
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Global accounting of locked value (USD-6).
    uint256 public totalUsdLocked;

    /// @notice Total number of deposits made.
    uint256 public depositCount;

    /// @notice Total number of withdrawals made.
    uint256 public withdrawalCount;

    /// @notice Balances[token][user] → amount in token units.
    mapping(address => mapping(address => uint256)) private balances;

    /// @notice Registered decimals for ERC-20 tokens (ETH = assumed 18).
    mapping(address => uint8) private tokenDecimals;

    // ═════════════════════════════════════════════════════════════════════════
    // 6. CONSTRUCTOR
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the KipuBankV2 contract.
     * @param _admin Address to be granted admin role.
     * @param _withdrawalThresholdWei Maximum amount of ETH that can be withdrawn per transaction.
     * @param _bankCapUsd6 Maximum total USD value (6 decimals) the bank can hold.
     * @param _ethUsdFeed Chainlink price feed address for ETH/USD.
     */
    constructor(
        address _admin,
        uint256 _withdrawalThresholdWei,
        uint256 _bankCapUsd6,
        address _ethUsdFeed
    ) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_ethUsdFeed == address(0)) revert ZeroAddress();
        if (_bankCapUsd6 == 0) revert ZeroAmount();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ROLE_ADMIN, _admin);

        withdrawalThresholdNative = _withdrawalThresholdWei;
        bankCapUsd = _bankCapUsd6;

        // Register ETH feed
        priceFeeds[NATIVE_TOKEN] = IAggregatorV3Interface(_ethUsdFeed);
        emit PriceFeedUpdated(NATIVE_TOKEN, _ethUsdFeed);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 7. MODIFIERS
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * @notice Restricts function access to bank administrators.
     */
    modifier onlyBankAdmin() {
        if (!hasRole(ROLE_ADMIN, msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @notice Validates that the amount is greater than zero.
     * @param _amount Amount to validate.
     */
    modifier validAmount(uint256 _amount) {
        if (_amount == 0) revert ZeroAmount();
        _;
    }

    /**
     * @notice Validates that ETH withdrawal is within the allowed threshold.
     * @param _amount Amount of ETH to withdraw.
     */
    modifier withinThreshold(uint256 _amount) {
        if (_amount > withdrawalThresholdNative) {
            revert WithdrawalThresholdExceeded(withdrawalThresholdNative);
        }
        _;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 8. FUNCIONES
    // ═════════════════════════════════════════════════════════════════════════

    // ─────────────────────────────────────────────────────────────────────────
    // Admin Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Registers a new ERC-20 token with its price feed and decimals.
     * @dev Only callable by ROLE_ADMIN. Required before users can deposit/withdraw the token.
     * @param _token Address of the ERC-20 token to register.
     * @param _feed Chainlink price feed address for this token.
     * @param _decimals Number of decimals the token uses.
     */
    function registerToken(address _token, address _feed, uint8 _decimals) external onlyBankAdmin {
        if (_token == address(0)) revert ZeroAddress();
        if (_feed == address(0)) revert ZeroAddress();
        
        tokenDecimals[_token] = _decimals;
        priceFeeds[_token] = IAggregatorV3Interface(_feed);
        
        emit TokenRegistered(_token, _decimals, _feed);
    }

    /**
     * @notice Updates the Chainlink price feed for ETH.
     * @dev Only callable by ROLE_ADMIN.
     * @param _feed New Chainlink price feed address for ETH/USD.
     */
    function updateEthFeed(address _feed) external onlyBankAdmin {
        if (_feed == address(0)) revert ZeroAddress();
        
        priceFeeds[NATIVE_TOKEN] = IAggregatorV3Interface(_feed);
        emit PriceFeedUpdated(NATIVE_TOKEN, _feed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deposit Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Deposits ETH into the bank.
     * @dev Converts ETH to USD-6 and checks against bank capacity.
     */
    function depositETH() external payable validAmount(msg.value) {
        // Calcular USD antes de modificar estado
        uint256 usd6 = _amountTokenToUsd6(NATIVE_TOKEN, msg.value);
        
        // 1 SOLO acceso de lectura a totalUsdLocked
        uint256 currentTotal = totalUsdLocked;
        uint256 newTotal = currentTotal + usd6;
        
        // Verificar capacidad UNA VEZ
        if (newTotal > bankCapUsd) {
            revert BankCapExceeded(bankCapUsd - currentTotal);
        }

        // 1 SOLO acceso de lectura a balance del usuario
        uint256 userBalance = balances[NATIVE_TOKEN][msg.sender];
        
        // Ya verificamos que no hay overflow en newTotal vs bankCapUsd
        // Por lo tanto userBalance + msg.value tampoco puede overflow
        unchecked {
            userBalance += msg.value;
        }

        // CEI: Effects - 2 escrituras a storage
        balances[NATIVE_TOKEN][msg.sender] = userBalance;
        totalUsdLocked = newTotal;
        
        unchecked {
            depositCount++;
        }

        emit Deposit(NATIVE_TOKEN, msg.sender, msg.value, usd6);
    }

    /**
     * @notice Deposits ERC-20 tokens into the bank.
     * @param _token Address of the ERC-20 token to deposit.
     * @param _amount Amount of tokens to deposit (in token's native decimals).
     */
    function depositERC20(address _token, uint256 _amount) external validAmount(_amount) {
        // Validaciones de configuración
        if (address(priceFeeds[_token]) == address(0)) revert FeedNotSet(_token);
        if (tokenDecimals[_token] == 0) revert DecimalsNotSet(_token);

        // Calcular USD antes de modificar estado
        uint256 usd6 = _amountTokenToUsd6(_token, _amount);
        
        // 1 SOLO acceso de lectura a totalUsdLocked
        uint256 currentTotal = totalUsdLocked;
        uint256 newTotal = currentTotal + usd6;
        
        // Verificar capacidad UNA VEZ
        if (newTotal > bankCapUsd) {
            revert BankCapExceeded(bankCapUsd - currentTotal);
        }

        // 1 SOLO acceso de lectura a balance del usuario
        uint256 userBalance = balances[_token][msg.sender];
        
        unchecked {
            userBalance += _amount;
        }

        // CEI: Effects - 2 escrituras a storage
        balances[_token][msg.sender] = userBalance;
        totalUsdLocked = newTotal;
        
        unchecked {
            depositCount++;
        }

        // CEI: Interaction - transferencia al final
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_token, msg.sender, _amount, usd6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Withdrawal Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Withdraws ETH from the bank.
     * @param _amount Amount of ETH to withdraw (in wei).
     */
    function withdrawETH(uint256 _amount) 
        external 
        validAmount(_amount)
        withinThreshold(_amount)
    {
        // 1 SOLO acceso de lectura a balance del usuario
        uint256 userBalance = balances[NATIVE_TOKEN][msg.sender];
        
        // Verificar fondos UNA VEZ (esto previene underflow)
        if (_amount > userBalance) {
            revert InsufficientFunds(userBalance);
        }
        
        // Calcular USD antes de modificar estado
        uint256 usd6 = _amountTokenToUsd6(NATIVE_TOKEN, _amount);
        
        // Ahora podemos usar unchecked porque YA verificamos
        unchecked {
            userBalance -= _amount;
        }
        
        // 1 SOLO acceso de lectura a totalUsdLocked
        uint256 currentTotal = totalUsdLocked;
        
        unchecked {
            currentTotal -= usd6; // safe porque usd6 se calculó desde _amount que está en userBalance
        }
        
        // CEI: Effects - 2 escrituras a storage
        balances[NATIVE_TOKEN][msg.sender] = userBalance;
        totalUsdLocked = currentTotal;
        
        unchecked {
            withdrawalCount++;
        }
        
        // CEI: Interaction - transferencia al final
        (bool ok, bytes memory data) = msg.sender.call{value: _amount}("");
        if (!ok) revert TransferFailed(data);

        emit Withdrawal(NATIVE_TOKEN, msg.sender, _amount, usd6);
    }

    /**
     * @notice Withdraws ERC-20 tokens from the bank.
     * @param _token Address of the ERC-20 token to withdraw.
     * @param _amount Amount of tokens to withdraw (in token's native decimals).
     */
    function withdrawERC20(address _token, uint256 _amount) external validAmount(_amount) {
        // Validaciones de configuración
        if (address(priceFeeds[_token]) == address(0)) revert FeedNotSet(_token);
        if (tokenDecimals[_token] == 0) revert DecimalsNotSet(_token);

        // 1 SOLO acceso de lectura a balance del usuario
        uint256 userBalance = balances[_token][msg.sender];
        
        // Verificar fondos UNA VEZ
        if (_amount > userBalance) {
            revert InsufficientFunds(userBalance);
        }
        
        // Calcular USD antes de modificar estado
        uint256 usd6 = _amountTokenToUsd6(_token, _amount);
        
        // Ahora podemos usar unchecked
        unchecked {
            userBalance -= _amount;
        }
        
        // 1 SOLO acceso de lectura a totalUsdLocked
        uint256 currentTotal = totalUsdLocked;
        
        unchecked {
            currentTotal -= usd6;
        }
        
        // CEI: Effects - 2 escrituras a storage
        balances[_token][msg.sender] = userBalance;
        totalUsdLocked = currentTotal;
        
        unchecked {
            withdrawalCount++;
        }

        // CEI: Interaction - transferencia al final
        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdrawal(_token, msg.sender, _amount, usd6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the balance of a specific token for a user.
     * @param _token Address of the token (use address(0) for ETH).
     * @param _user Address of the user.
     * @return The balance in token's native units.
     */
    function getBalance(address _token, address _user) external view returns (uint256) {
        return balances[_token][_user];
    }

    /**
     * @notice Returns the Chainlink price feed address for a token.
     * @param _token Address of the token.
     * @return Address of the price feed.
     */
    function getFeed(address _token) external view returns (address) {
        return address(priceFeeds[_token]);
    }

    /**
     * @notice Returns the registered decimals for a token.
     * @param _token Address of the token.
     * @return Number of decimals.
     */
    function getTokenDecimals(address _token) external view returns (uint8) {
        return tokenDecimals[_token];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal Helper Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Converts a token amount to USD with 6 decimals using Chainlink price feeds.
     * @dev Handles different token decimals and feed decimals to normalize to USD-6.
     * @param _token Address of the token (address(0) for ETH).
     * @param _amount Amount in token's native decimals.
     * @return usd6 The equivalent value in USD with 6 decimals.
     */
    function _amountTokenToUsd6(address _token, uint256 _amount) private view returns (uint256 usd6) {
        IAggregatorV3Interface feed = priceFeeds[_token];
        if (address(feed) == address(0)) revert FeedNotSet(_token);

        (, int256 price, , , ) = feed.latestRoundData();
        if (price <= 0) revert InvalidPrice();

        uint8 feedDecimals = feed.decimals();
        uint8 tknDec = _token == NATIVE_TOKEN ? 18 : tokenDecimals[_token];
        
        if (_token != NATIVE_TOKEN && tknDec == 0) revert DecimalsNotSet(_token);

        // Formula: usd6 = (_amount * price) / (10^(tknDec + feedDecimals - USD_DECIMALS))
        uint256 num = _amount * uint256(price);
        uint256 denomExp = uint256(tknDec) + uint256(feedDecimals);

        if (denomExp >= USD_DECIMALS) {
            usd6 = num / (10 ** (denomExp - USD_DECIMALS));
        } else {
            usd6 = num * (10 ** (USD_DECIMALS - denomExp));
        }
    }
}