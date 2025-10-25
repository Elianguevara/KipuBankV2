// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*///////////////////////////
            IMPORTS
///////////////////////////*/
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 * @author Elian
 * @notice Bank with unified accounting in USD-6. Supports ETH (via Chainlink) and USDC.
 * @dev address(0) => ETH; USDC is taken 1:1 in 6 decimals. CEI + ReentrancyGuard + Pausable + Roles.
 * 
 * Architecture:
 * - All balances are stored internally in USD-6 (6 decimals)
 * - ETH deposits are converted to USD-6 using Chainlink price feed
 * - USDC deposits are assumed 1:1 with USD-6
 * - Withdrawals convert from USD-6 back to native token amounts
 * 
 * Security Features:
 * - Checks-Effects-Interactions pattern
 * - ReentrancyGuard on all state-changing functions
 * - Role-based access control
 * - Oracle staleness and validity checks
 * - Pausable for emergency stops
 */
contract KipuBankV2 is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*///////////////////////////
           TYPE DECLARATIONS
    ///////////////////////////*/
    /// @notice Role for pausing/unpausing the contract
    bytes32 public constant PAUSER_ROLE    = keccak256("PAUSER_ROLE");
    
    /// @notice Role for treasury operations (rescue funds)
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    /*///////////////////////////
        CONSTANTS / IMMUTABLES
    ///////////////////////////*/
    /// @notice Maximum accepted heartbeat for price (staleness check)
    uint32  public constant ORACLE_HEARTBEAT = 3600; // 1 hour
    
    /// @notice Internal ledger decimals (USD-6)
    uint8   public constant USD_DECIMALS = 6;
    
    /// @notice Unit 1 USD-6
    uint256 private constant ONE_USD6 = 10 ** USD_DECIMALS;

    /// @notice USDC token (6 decimals) - immutable after deployment
    IERC20 public immutable USDC;
    
    /// @notice ETH/USD price feed - immutable after deployment
    AggregatorV3Interface public immutable ETH_USD_FEED;
    
    /// @notice Decimals of the Chainlink price feed - cached for gas optimization
    uint8 public immutable FEED_DECIMALS;

    /// @notice Maximum withdrawal threshold per transaction in USD-6
    uint256 public immutable WITHDRAWAL_THRESHOLD_USD6;

    /// @notice Contract version
    string public constant VERSION = "2.0.0";

    /*///////////////////////////
               STATE
    ///////////////////////////*/
    /// @notice Ledger: balance per user and per "logical token" (always USD-6)
    /// @dev token = address(0) => ETH; token = address(USDC) => USDC
    mapping(address user => mapping(address token => uint256 usd6)) private s_balances;

    /// @notice Total bank balance in USD-6 (sum of all balances)
    uint256 public s_totalUSD6;

    /// @notice Global bank capacity limit (USD-6)
    uint256 public s_bankCapUSD6;

    /// @notice Counter for deposits (observability)
    uint256 public s_depositCount;
    
    /// @notice Counter for withdrawals (observability)
    uint256 public s_withdrawCount;

    /*///////////////////////////
              EVENTS
    ///////////////////////////*/
    /**
     * @notice Emitted when a user deposits tokens
     * @param user Address of the depositor
     * @param token Token address (address(0) for ETH)
     * @param amountToken Amount in native token (ETH-wei or USDC-6)
     * @param creditedUSD6 Amount credited in USD-6
     */
    event KBV2_Deposit(
        address indexed user,
        address indexed token,
        uint256 amountToken,
        uint256 creditedUSD6
    );

    /**
     * @notice Emitted when a user withdraws tokens
     * @param user Address of the withdrawer
     * @param token Token address (address(0) for ETH)
     * @param debitedUSD6 Amount debited from ledger in USD-6
     * @param amountTokenSent Amount sent in native token (ETH-wei or USDC-6)
     */
    event KBV2_Withdrawal(
        address indexed user,
        address indexed token,
        uint256 debitedUSD6,
        uint256 amountTokenSent
    );

    /**
     * @notice Emitted when bank capacity is updated
     * @param newCapUSD6 New capacity limit in USD-6
     */
    event KBV2_BankCapUpdated(uint256 newCapUSD6);

    /*///////////////////////////
               ERRORS
    ///////////////////////////*/
    /// @notice Thrown when amount is zero
    error KBV2_ZeroAmount();
    
    /// @notice Thrown when bank capacity would be exceeded
    error KBV2_CapExceeded();
    
    /// @notice Thrown when user has insufficient balance
    error KBV2_InsufficientBalance();
    
    /// @notice Thrown when oracle data is compromised
    error KBV2_OracleCompromised();
    
    /// @notice Thrown when oracle price is stale
    error KBV2_StalePrice();
    
    /// @notice Thrown when withdrawal exceeds per-transaction limit
    error KBV2_WithdrawalLimitExceeded();
    
    /// @notice Thrown when ETH transfer fails
    error KBV2_ETHTransferFailed();
    
    /// @notice Thrown when constructor parameters are invalid
    error KBV2_InvalidParameters();
    
    /// @notice Thrown when user tries to send ETH via receive()
    error KBV2_UseDepositETH();

    /*///////////////////////////
             CONSTRUCTOR
    ///////////////////////////*/
    /**
     * @notice Initializes the KipuBankV2 contract
     * @param admin Initial EOA with DEFAULT_ADMIN_ROLE/PAUSER/TREASURER
     * @param usdc USDC token address (6 decimals) on testnet
     * @param ethUsdFeed Chainlink Aggregator ETH/USD address
     * @param bankCapUSD6 Global bank capacity (USD-6)
     * @param withdrawalThresholdUSD6 Per-transaction withdrawal limit (USD-6)
     */
    constructor(
        address admin,
        address usdc,
        address ethUsdFeed,
        uint256 bankCapUSD6,
        uint256 withdrawalThresholdUSD6
    ) {
        // Validate addresses
        if (admin == address(0) || usdc == address(0) || ethUsdFeed == address(0)) {
            revert KBV2_InvalidParameters();
        }
        
        // Validate capacity parameters
        if (bankCapUSD6 == 0 || withdrawalThresholdUSD6 == 0 || withdrawalThresholdUSD6 > bankCapUSD6) {
            revert KBV2_InvalidParameters();
        }
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(TREASURER_ROLE, admin);

        // Set immutable variables
        USDC = IERC20(usdc);
        ETH_USD_FEED = AggregatorV3Interface(ethUsdFeed);
        FEED_DECIMALS = ETH_USD_FEED.decimals();
        s_bankCapUSD6 = bankCapUSD6;
        WITHDRAWAL_THRESHOLD_USD6 = withdrawalThresholdUSD6;
    }

    /*///////////////////////////
             MODIFIERS
    ///////////////////////////*/
    /**
     * @notice Ensures amount is not zero
     * @param amount Amount to validate
     */
    modifier nonZero(uint256 amount) {
        if (amount == 0) revert KBV2_ZeroAmount();
        _;
    }

    /**
     * @notice Enforces bank capacity limit
     * @param newTotalUSD6 New total after operation
     */
    modifier enforceCap(uint256 newTotalUSD6) {
        if (newTotalUSD6 > s_bankCapUSD6) revert KBV2_CapExceeded();
        _;
    }

    /**
     * @notice Validates withdrawal amount and user balance
     * @param user User address
     * @param token Token address
     * @param usd6Amount Amount in USD-6 to withdraw
     */
    modifier validWithdraw(address user, address token, uint256 usd6Amount) {
        if (usd6Amount == 0) revert KBV2_ZeroAmount();
        if (usd6Amount > WITHDRAWAL_THRESHOLD_USD6) revert KBV2_WithdrawalLimitExceeded();
        
        uint256 bal = s_balances[user][token];
        if (usd6Amount > bal) revert KBV2_InsufficientBalance();
        _;
    }

    /*///////////////////////////
             DEPOSITS
    ///////////////////////////*/
    /**
     * @notice Deposits ETH and credits equivalent USD-6 to user's balance
     * @dev Converts ETH to USD-6 using Chainlink oracle
     * @dev msg.value Amount of ETH to deposit (in wei)
     */
    function depositETH()
        external
        payable
        whenNotPaused
        nonReentrant
        nonZero(msg.value)
        enforceCap(s_totalUSD6 + _ethWeiToUSD6(msg.value))
    {
        // Calculate USD-6 equivalent
        uint256 usd6 = _ethWeiToUSD6(msg.value);

        // Effects (single storage write)
        unchecked {
            s_balances[msg.sender][address(0)] += usd6;
            s_totalUSD6 += usd6;
            s_depositCount++;
        }

        emit KBV2_Deposit(msg.sender, address(0), msg.value, usd6);
    }

    /**
     * @notice Deposits USDC and credits equivalent USD-6 to user's balance
     * @dev Assumes USDC has 6 decimals (1:1 conversion with USD-6)
     * @param amountUSDC Amount of USDC to deposit (6 decimals)
     */
    function depositUSDC(uint256 amountUSDC)
        external
        whenNotPaused
        nonReentrant
        nonZero(amountUSDC)
        enforceCap(s_totalUSD6 + amountUSDC)
    {
        // Effects first (CEI pattern)
        unchecked {
            s_balances[msg.sender][address(USDC)] += amountUSDC;
            s_totalUSD6 += amountUSDC;
            s_depositCount++;
        }

        // Interaction
        USDC.safeTransferFrom(msg.sender, address(this), amountUSDC);

        emit KBV2_Deposit(msg.sender, address(USDC), amountUSDC, amountUSDC);
    }

    /*///////////////////////////
              WITHDRAWALS
    ///////////////////////////*/
    /**
     * @notice Withdraws ETH by debiting USD-6 from user's balance
     * @dev Converts USD-6 to ETH using Chainlink oracle
     * @param usd6Amount Amount in USD-6 to withdraw
     */
    function withdrawETH(uint256 usd6Amount)
        external
        whenNotPaused
        nonReentrant
        validWithdraw(msg.sender, address(0), usd6Amount)
    {
        // Effects (single read + single write)
        unchecked {
            s_balances[msg.sender][address(0)] -= usd6Amount;
            s_totalUSD6 -= usd6Amount;
            s_withdrawCount++;
        }

        // Convert and send (interaction)
        uint256 weiAmount = _usd6ToEthWei(usd6Amount);
        (bool ok, ) = payable(msg.sender).call{value: weiAmount}("");
        if (!ok) revert KBV2_ETHTransferFailed();

        emit KBV2_Withdrawal(msg.sender, address(0), usd6Amount, weiAmount);
    }

    /**
     * @notice Withdraws USDC by debiting USD-6 from user's balance
     * @dev 1:1 conversion between USD-6 and USDC
     * @param usd6Amount Amount in USD-6 to withdraw
     */
    function withdrawUSDC(uint256 usd6Amount)
        external
        whenNotPaused
        nonReentrant
        validWithdraw(msg.sender, address(USDC), usd6Amount)
    {
        // Effects (single read + single write)
        unchecked {
            s_balances[msg.sender][address(USDC)] -= usd6Amount;
            s_totalUSD6 -= usd6Amount;
            s_withdrawCount++;
        }

        // Send USDC 1:1
        USDC.safeTransfer(msg.sender, usd6Amount);

        emit KBV2_Withdrawal(msg.sender, address(USDC), usd6Amount, usd6Amount);
    }

    /*///////////////////////////
           ADMINISTRATION
    ///////////////////////////*/
    /**
     * @notice Updates the global bank capacity
     * @param newCap New capacity in USD-6
     */
    function setBankCapUSD6(uint256 newCap)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newCap == 0) revert KBV2_InvalidParameters();
        s_bankCapUSD6 = newCap;
        emit KBV2_BankCapUpdated(newCap);
    }

    /**
     * @notice Pauses all deposits and withdrawals
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all deposits and withdrawals
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Rescues tokens/ETH sent to contract by mistake
     * @dev Does not touch user balances, only excess funds
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to rescue
     */
    function rescue(address token, uint256 amount)
        external
        onlyRole(TREASURER_ROLE)
    {
        if (token == address(0)) {
            (bool ok, ) = payable(msg.sender).call{value: amount}("");
            if (!ok) revert KBV2_ETHTransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /*///////////////////////////
           VIEW FUNCTIONS
    ///////////////////////////*/
    /**
     * @notice Gets user's balance for a specific token in USD-6
     * @param user User address
     * @param token Token address (address(0) for ETH)
     * @return Balance in USD-6
     */
    function getBalanceUSD6(address user, address token) external view returns (uint256) {
        return s_balances[user][token];
    }

    /**
     * @notice Gets user's total balance across all tokens in USD-6
     * @param user User address
     * @return Total balance in USD-6
     */
    function getTotalBalanceUSD6(address user) external view returns (uint256) {
        return s_balances[user][address(0)] + s_balances[user][address(USDC)];
    }

    /**
     * @notice Gets current ETH price in USD with decimals
     * @return price Current ETH/USD price
     * @return decimals Number of decimals in the price
     */
    function getETHPrice() external view returns (uint256 price, uint8 decimals) {
        return _validatedEthUsdPrice();
    }

    /**
     * @notice Previews how much ETH (wei) would be received for a USD-6 amount
     * @param usd6Amount Amount in USD-6
     * @return weiAmount Equivalent amount in wei
     */
    function previewUSD6ToETH(uint256 usd6Amount) external view returns (uint256 weiAmount) {
        return _usd6ToEthWei(usd6Amount);
    }

    /**
     * @notice Previews how much USD-6 would be credited for an ETH amount
     * @param weiAmount Amount in wei
     * @return usd6Amount Equivalent amount in USD-6
     */
    function previewETHToUSD6(uint256 weiAmount) external view returns (uint256 usd6Amount) {
        return _ethWeiToUSD6(weiAmount);
    }

    /*///////////////////////////
        INTERNAL UTILITIES
    ///////////////////////////*/
    /**
     * @notice Validates oracle data and returns price with decimals
     * @dev Checks for stale data and compromised rounds
     * @return price ETH/USD price
     * @return pDec Number of decimals in the price
     */
    function _validatedEthUsdPrice() internal view returns (uint256 price, uint8 pDec) {
        (uint80 rid, int256 p, , uint256 updatedAt, uint80 ansInRound) = ETH_USD_FEED.latestRoundData();
        
        // Validate price and round
        if (p <= 0 || ansInRound < rid) revert KBV2_OracleCompromised();
        
        // Check staleness
        if (block.timestamp - updatedAt > ORACLE_HEARTBEAT) revert KBV2_StalePrice();
        
        pDec = FEED_DECIMALS;
        price = uint256(p);
    }

    /**
     * @notice Converts ETH (wei) to USD-6
     * @dev Formula: USD-6 = wei * price / 10^(pDec + 12)
     * @param weiAmount Amount in wei
     * @return USD-6 amount
     */
    function _ethWeiToUSD6(uint256 weiAmount) internal view returns (uint256) {
        (uint256 price, uint8 pDec) = _validatedEthUsdPrice();
        return (weiAmount * price) / (10 ** (uint256(pDec) + 12));
    }

    /**
     * @notice Converts USD-6 to ETH (wei)
     * @dev Formula: wei = USD-6 * 10^(pDec + 12) / price
     * @param usd6Amount Amount in USD-6
     * @return wei amount
     */
    function _usd6ToEthWei(uint256 usd6Amount) internal view returns (uint256) {
        (uint256 price, uint8 pDec) = _validatedEthUsdPrice();
        return (usd6Amount * (10 ** (uint256(pDec) + 12))) / price;
    }

    /*///////////////////////////
              RECEIVE
    ///////////////////////////*/
    /**
     * @notice Prevents accidental ETH transfers
     * @dev Users must use depositETH() function
     */
    receive() external payable {
        revert KBV2_UseDepositETH();
    }
}