// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

/**
 * @title KipuBankV3
 * @author Elian (upgraded by ChatGPT)
 * @notice Multi-asset bank that routes every supported deposit to USDC using Uniswap V2.
 * @dev Extends the security model from V2 (roles, pausability, reentrancy guard) while
 *      introducing token swaps. All internal accounting is performed in USDC (6 decimals).
 */
contract KipuBankV3 is AccessControl, Pausable, ReentrancyGuard {
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
    /// @notice Internal ledger decimals (USDC uses 6 decimals)
    uint8 public constant USD_DECIMALS = 6;

    /// @notice Contract version
    string public constant VERSION = "3.0.0";

    /// @notice USDC token (6 decimals) - immutable after deployment
    IERC20 public immutable USDC;

    /// @notice UniswapV2 router used for all swaps
    IUniswapV2Router02 public immutable ROUTER;

    /// @notice Wrapped native token used by router
    address public immutable WETH;

    /// @notice Maximum withdrawal threshold per transaction in USD-6
    uint256 public immutable WITHDRAWAL_THRESHOLD_USD6;

    /*///////////////////////////
               STATE
    ///////////////////////////*/
    /// @notice Ledger: user -> logical token -> balance in USD-6
    /// @dev token = address(USDC) => actual bank balance, token = address(0) reserved for backwards compatibility
    mapping(address user => mapping(address token => uint256 usd6)) private s_balances;

    /// @notice Total bank balance in USD-6 (sum of all user balances)
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
     * @notice Emitted when a user deposits tokens that are swapped to USDC
     * @param user Address of the depositor
     * @param tokenIn Token address provided by the user (address(0) for native ETH)
     * @param amountIn Amount of token provided (wei for ETH, decimals for ERC20)
     * @param amountUSDCReceived Amount of USDC credited in the ledger (6 decimals)
     */
    event KBV3_Deposit(
        address indexed user,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountUSDCReceived
    );

    /**
     * @notice Emitted when a user withdraws value from the bank
     * @param user Address of the withdrawer
     * @param tokenOut Token that was withdrawn (address(0) for ETH, address(USDC) for USDC)
     * @param debitedUSD6 Amount debited from ledger in USD-6
     * @param amountTokenOut Amount actually sent to the user (wei for ETH, decimals for ERC20)
     */
    event KBV3_Withdrawal(
        address indexed user,
        address indexed tokenOut,
        uint256 debitedUSD6,
        uint256 amountTokenOut
    );

    /**
     * @notice Emitted when bank capacity is updated
     * @param newCapUSD6 New capacity limit in USD-6
     */
    event KBV3_BankCapUpdated(uint256 newCapUSD6);

    /*///////////////////////////
               ERRORS
    ///////////////////////////*/
    /// @notice Thrown when amount is zero
    error KBV3_ZeroAmount();

    /// @notice Thrown when bank capacity would be exceeded
    error KBV3_CapExceeded();

    /// @notice Thrown when user has insufficient balance
    error KBV3_InsufficientBalance();

    /// @notice Thrown when withdrawal exceeds per-transaction limit
    error KBV3_WithdrawalLimitExceeded();

    /// @notice Thrown when ETH transfer fails
    error KBV3_ETHTransferFailed();

    /// @notice Thrown when constructor parameters are invalid
    error KBV3_InvalidParameters();

    /// @notice Thrown when deadline for swap has already passed
    error KBV3_ExpiredDeadline();

    /// @notice Thrown when attempting to use unsupported token address
    error KBV3_UnsupportedToken();

    /// @notice Thrown when swap path does not return amounts
    error KBV3_InvalidSwap();

    /*///////////////////////////
             CONSTRUCTOR
    ///////////////////////////*/
    /**
     * @notice Initializes the KipuBankV3 contract
     * @param admin Initial EOA with DEFAULT_ADMIN_ROLE/PAUSER/TREASURER
     * @param usdc USDC token address (6 decimals)
     * @param router Uniswap V2 router address to use for swaps
     * @param bankCapUSD6 Global bank capacity (USD-6)
     * @param withdrawalThresholdUSD6 Per-transaction withdrawal limit (USD-6)
     */
    constructor(
        address admin,
        address usdc,
        address router,
        uint256 bankCapUSD6,
        uint256 withdrawalThresholdUSD6
    ) {
        if (
            admin == address(0) ||
            usdc == address(0) ||
            router == address(0) ||
            bankCapUSD6 == 0 ||
            withdrawalThresholdUSD6 == 0 ||
            withdrawalThresholdUSD6 > bankCapUSD6
        ) {
            revert KBV3_InvalidParameters();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(TREASURER_ROLE, admin);

        USDC = IERC20(usdc);
        ROUTER = IUniswapV2Router02(router);
        WETH = ROUTER.WETH();
        s_bankCapUSD6 = bankCapUSD6;
        WITHDRAWAL_THRESHOLD_USD6 = withdrawalThresholdUSD6;
    }

    /*///////////////////////////
             MODIFIERS
    ///////////////////////////*/
    modifier nonZero(uint256 amount) {
        if (amount == 0) revert KBV3_ZeroAmount();
        _;
    }

    modifier enforceCap(uint256 newTotalUSD6) {
        if (newTotalUSD6 > s_bankCapUSD6) revert KBV3_CapExceeded();
        _;
    }

    modifier ensureDeadline(uint256 deadline) {
        if (deadline < block.timestamp) revert KBV3_ExpiredDeadline();
        _;
    }

    modifier validWithdraw(uint256 usd6Amount) {
        if (usd6Amount == 0) revert KBV3_ZeroAmount();
        if (usd6Amount > WITHDRAWAL_THRESHOLD_USD6) revert KBV3_WithdrawalLimitExceeded();

        uint256 bal = s_balances[msg.sender][address(USDC)];
        if (usd6Amount > bal) revert KBV3_InsufficientBalance();
        _;
    }

    /*///////////////////////////
             DEPOSITS
    ///////////////////////////*/
    /**
     * @notice Deposits native ETH, swaps it to USDC, and credits the user balance.
     * @param minUSDCOut Minimum acceptable USDC from swap (slippage control)
     * @param deadline Timestamp after which the transaction reverts
     */
    function depositETH(uint256 minUSDCOut, uint256 deadline)
        external
        payable
        whenNotPaused
        nonReentrant
        nonZero(msg.value)
        ensureDeadline(deadline)
    {
        address[] memory path = _pathFromETH();
        uint256 quoted = _quote(msg.value, path);
        uint256 projectedTotal = s_totalUSD6 + quoted;
        if (projectedTotal > s_bankCapUSD6) revert KBV3_CapExceeded();

        uint256[] memory amounts = ROUTER.swapExactETHForTokens{value: msg.value}(
            minUSDCOut,
            path,
            address(this),
            deadline
        );
        uint256 usdcReceived = amounts[amounts.length - 1];
        uint256 newTotal = s_totalUSD6 + usdcReceived;
        if (newTotal > s_bankCapUSD6) revert KBV3_CapExceeded();

        _credit(msg.sender, usdcReceived);
        emit KBV3_Deposit(msg.sender, address(0), msg.value, usdcReceived);
    }

    /**
     * @notice Deposits USDC directly without swaps.
     * @param amountUSDC Amount of USDC to deposit (6 decimals)
     */
    function depositUSDC(uint256 amountUSDC)
        public
        whenNotPaused
        nonReentrant
        nonZero(amountUSDC)
        enforceCap(s_totalUSD6 + amountUSDC)
    {
        _depositUSDC(amountUSDC, msg.sender);
    }

    /**
     * @notice Deposits an arbitrary ERC20 supported by Uniswap V2.
     * @param tokenIn Address of the ERC20 being deposited (must have a direct USDC pair)
     * @param amountIn Amount of `tokenIn` to deposit
     * @param minUSDCOut Minimum acceptable USDC from the swap
     * @param deadline Timestamp after which the transaction reverts
     */
    function depositToken(
        address tokenIn,
        uint256 amountIn,
        uint256 minUSDCOut,
        uint256 deadline
    )
        external
        whenNotPaused
        nonReentrant
        nonZero(amountIn)
        ensureDeadline(deadline)
    {
        if (tokenIn == address(0)) revert KBV3_UnsupportedToken();
        if (tokenIn == address(USDC)) {
            _depositUSDC(amountIn, msg.sender);
            return;
        }

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        address[] memory path = _path(tokenIn, address(USDC));
        uint256 quoted = _quote(amountIn, path);
        uint256 projectedTotal = s_totalUSD6 + quoted;
        if (projectedTotal > s_bankCapUSD6) revert KBV3_CapExceeded();

        IERC20(tokenIn).safeIncreaseAllowance(address(ROUTER), amountIn);
        uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
            amountIn,
            minUSDCOut,
            path,
            address(this),
            deadline
        );
        IERC20(tokenIn).safeApprove(address(ROUTER), 0);

        uint256 usdcReceived = amounts[amounts.length - 1];
        uint256 newTotal = s_totalUSD6 + usdcReceived;
        if (newTotal > s_bankCapUSD6) revert KBV3_CapExceeded();

        _credit(msg.sender, usdcReceived);
        emit KBV3_Deposit(msg.sender, tokenIn, amountIn, usdcReceived);
    }

    /*///////////////////////////
              WITHDRAWALS
    ///////////////////////////*/
    /**
     * @notice Withdraws USDC debiting the user balance.
     * @param usd6Amount Amount in USD-6 to withdraw
     */
    function withdrawUSDC(uint256 usd6Amount)
        external
        whenNotPaused
        nonReentrant
        validWithdraw(usd6Amount)
    {
        _debit(msg.sender, usd6Amount);
        USDC.safeTransfer(msg.sender, usd6Amount);

        emit KBV3_Withdrawal(msg.sender, address(USDC), usd6Amount, usd6Amount);
    }

    /**
     * @notice Withdraws ETH by swapping USDC through Uniswap V2.
     * @param usd6Amount Amount in USD-6 to withdraw
     * @param minETHOut Minimum acceptable ETH from the swap
     * @param deadline Timestamp after which the transaction reverts
     */
    function withdrawETH(
        uint256 usd6Amount,
        uint256 minETHOut,
        uint256 deadline
    )
        external
        whenNotPaused
        nonReentrant
        ensureDeadline(deadline)
        validWithdraw(usd6Amount)
    {
        _debit(msg.sender, usd6Amount);

        address[] memory path = _path(address(USDC), address(0));

        USDC.safeIncreaseAllowance(address(ROUTER), usd6Amount);
        uint256[] memory amounts = ROUTER.swapExactTokensForETH(
            usd6Amount,
            minETHOut,
            path,
            address(this),
            deadline
        );
        USDC.safeApprove(address(ROUTER), 0);

        uint256 ethReceived = amounts[amounts.length - 1];
        (bool ok, ) = payable(msg.sender).call{value: ethReceived}("");
        if (!ok) revert KBV3_ETHTransferFailed();

        emit KBV3_Withdrawal(msg.sender, address(0), usd6Amount, ethReceived);
    }

    /*///////////////////////////
           ADMINISTRATION
    ///////////////////////////*/
    function setBankCapUSD6(uint256 newCap)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newCap == 0) revert KBV3_InvalidParameters();
        s_bankCapUSD6 = newCap;
        emit KBV3_BankCapUpdated(newCap);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function rescue(address token, uint256 amount)
        external
        onlyRole(TREASURER_ROLE)
    {
        if (token == address(0)) {
            (bool ok, ) = payable(msg.sender).call{value: amount}("");
            if (!ok) revert KBV3_ETHTransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /*///////////////////////////
           VIEW FUNCTIONS
    ///////////////////////////*/
    function getBalanceUSD6(address user, address token) external view returns (uint256) {
        if (token == address(USDC)) {
            return s_balances[user][address(USDC)];
        }
        if (token == address(0)) {
            return s_balances[user][address(0)];
        }
        return 0;
    }

    function getTotalBalanceUSD6(address user) external view returns (uint256) {
        return s_balances[user][address(USDC)] + s_balances[user][address(0)];
    }

    function previewDeposit(address tokenIn, uint256 amountIn) external view returns (uint256) {
        if (amountIn == 0) return 0;
        if (tokenIn == address(USDC)) return amountIn;
        address[] memory path = tokenIn == address(0)
            ? _pathFromETH()
            : _path(tokenIn, address(USDC));
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        if (amounts.length == 0) revert KBV3_InvalidSwap();
        return amounts[amounts.length - 1];
    }

    function previewWithdrawETH(uint256 usd6Amount) external view returns (uint256) {
        if (usd6Amount == 0) return 0;
        address[] memory path = _path(address(USDC), address(0));
        uint256[] memory amounts = ROUTER.getAmountsOut(usd6Amount, path);
        if (amounts.length == 0) revert KBV3_InvalidSwap();
        return amounts[amounts.length - 1];
    }

    /*///////////////////////////
        INTERNAL UTILITIES
    ///////////////////////////*/
    function _credit(address user, uint256 usd6Amount) internal {
        unchecked {
            s_balances[user][address(USDC)] += usd6Amount;
            s_totalUSD6 += usd6Amount;
            s_depositCount++;
        }
    }

    function _debit(address user, uint256 usd6Amount) internal {
        unchecked {
            s_balances[user][address(USDC)] -= usd6Amount;
            s_totalUSD6 -= usd6Amount;
            s_withdrawCount++;
        }
    }

    function _depositUSDC(uint256 amountUSDC, address user) internal {
        _credit(user, amountUSDC);
        USDC.safeTransferFrom(user, address(this), amountUSDC);

        emit KBV3_Deposit(user, address(USDC), amountUSDC, amountUSDC);
    }

    function _pathFromETH() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = WETH;
        path[1] = address(USDC);
    }

    function _path(address tokenIn, address tokenOut) internal view returns (address[] memory path) {
        if (tokenIn == address(0)) {
            return _pathFromETH();
        }
        if (tokenOut == address(0)) {
            path = new address[](2);
            path[0] = address(USDC);
            path[1] = WETH;
            return path;
        }
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function _quote(uint256 amountIn, address[] memory path) internal view returns (uint256) {
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        if (amounts.length == 0) revert KBV3_InvalidSwap();
        return amounts[amounts.length - 1];
    }

    /*///////////////////////////
              RECEIVE
    ///////////////////////////*/
    receive() external payable {
        revert KBV3_UnsupportedToken();
    }
}
