# KipuBankV2

## High-level Improvements

KipuBankV2 is an evolution of the original **KipuBank** smart contract.  
The improvements focus on **security**, **multi-token support**, **unified accounting**, and **gas efficiency**, making the contract closer to a production-ready design.

- **Security**:

  - Role-based access control with OpenZeppelin `AccessControl`.
  - `Pausable` to stop all deposits/withdrawals in case of emergency.
  - `ReentrancyGuard` to prevent reentrancy attacks.
  - Custom errors instead of `require` strings for better gas efficiency.

- **Multi-token support**:

  - ETH deposits are converted into USD-6 using Chainlink price feeds.
  - USDC deposits are handled 1:1 with USD-6.
  - Withdrawals can be executed in ETH or USDC.

- **Unified accounting**:

  - All balances are stored in USD-6 (6 decimals).
  - Nested mapping `s_balances[user][token]` to track each user’s per-token balance.
  - `address(0)` represents ETH, `address(USDC)` represents USDC.

- **Oracle integration**:

  - Chainlink ETH/USD feed for fair conversion rates.
  - Staleness and compromised data checks to ensure reliability.

- **Gas efficiency**:
  - Single storage read + write operations where possible.
  - `immutable` and `constant` variables to save gas.
  - Strict **Checks-Effects-Interactions** pattern.

---

## Deployment Instructions

### Requirements

- **Remix IDE** or Hardhat/Foundry environment.
- **MetaMask** wallet connected to **Sepolia Testnet**.
- Testnet ETH for gas (can be obtained from a [Sepolia faucet](https://sepoliafaucet.com/)).

### Steps (Remix + MetaMask)

1. Open **Remix IDE** at [https://remix.ethereum.org](https://remix.ethereum.org).
2. Load the contract `KipuBankV2.sol` into your workspace.
3. In the **Solidity Compiler** tab:
   - Select compiler version **0.8.26**.
   - Enable optimization with **200 runs**.
   - Compile the contract.
4. In the **Deploy & Run Transactions** tab:
   - Environment: `Injected Provider - MetaMask`.
   - Contract: `KipuBankV2`.
   - Constructor arguments (example):
     - `admin`: `YOUR_ADDRESS`
     - `usdc`: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
     - `ethUsdFeed`: `0x694AA1769357215DE4FAC081bf1f309aDC325306`
     - `bankCapUSD6`: `1000000000000` (1,000,000 USD-6 cap)
     - `withdrawalThresholdUSD6`: `10000000000` (10,000 USD-6 threshold)
   - Click **Deploy** and confirm the transaction in MetaMask.
5. Once deployed, copy the contract address (shown in Remix console or MetaMask tx receipt).
6. Verify the contract on **Sepolia Etherscan**:
   - Compiler: `0.8.26`.
   - Optimization: `200 runs`.
   - Paste the source code.
   - Paste ABI-encoded constructor arguments (generated in Remix console with `ethers.utils.defaultAbiCoder`).
   - Submit for verification.

---

## Interaction Instructions

After verification, the contract can be interacted with directly on **Sepolia Etherscan**:  
👉 [KipuBankV2 on Sepolia Etherscan](https://sepolia.etherscan.io/address/0x0Cbb2fA554128647EB82e41bfb60B70fCf2bDc27#code)

### Read-only Functions (no gas required)

- `getBalanceUSD6(user, token)` → Returns a user’s balance in USD-6.
- `getTotalBalanceUSD6(user)` → Returns total balance across ETH + USDC.
- `getETHPrice()` → Returns latest ETH/USD price and decimals.
- `previewETHToUSD6(weiAmount)` → Simulates ETH → USD-6 conversion.
- `previewUSD6ToETH(usd6Amount)` → Simulates USD-6 → ETH conversion.

### State-changing Functions (require MetaMask + Sepolia ETH)

1. **Deposit ETH**

   - Go to `Write Contract` → `depositETH()`.
   - Enter the amount of ETH in the "Value" field (e.g., `0.01`).
   - Confirm the transaction in MetaMask.
   - Your balance will be credited in USD-6 internally.

2. **Deposit USDC**

   - Call `depositUSDC(uint256 amount)`.
   - First approve USDC spending from your MetaMask (standard ERC-20 `approve`).
   - Confirm the transaction.

3. **Withdraw ETH**

   - Call `withdrawETH(uint256 usd6Amount)`.
   - Example: `1000000` to withdraw ≈ 1 USD worth of ETH.
   - Confirm in MetaMask, ETH will be sent to your wallet.

4. **Withdraw USDC**

   - Call `withdrawUSDC(uint256 usd6Amount)`.
   - Example: `5000000` to withdraw 5 USDC.

5. **Pause/Unpause** (Admin only)

   - Call `pause()` to disable deposits/withdrawals.
   - Call `unpause()` to re-enable.

6. **Rescue funds** (Treasurer only)
   - Call `rescue(address token, uint256 amount)` to recover ERC-20 or ETH mistakenly sent to the contract.
   - `token = address(0)` for ETH.

---

## Design Decisions and Trade-offs

- **Unified USD-6 ledger**: Simplifies multi-asset tracking but introduces dependency on Chainlink for ETH valuation.
- **Role-based access**: More secure and flexible than a single-owner model, but requires careful role assignment.
- **Chainlink oracle dependency**: Ensures accurate ETH/USD conversion, but introduces reliance on external infrastructure.
- **Gas optimization vs readability**: Optimizations (unchecked arithmetic, minimal storage reads) reduce gas costs but slightly reduce code readability.
- **Custom errors**: More efficient than `require` strings, but less descriptive for non-technical users reviewing transactions.

---
