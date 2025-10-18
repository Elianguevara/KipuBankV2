# KipuBankV2

## 📌 Project Overview

KipuBankV2 is the evolution of the original KipuBank contract, refactored and extended to simulate a robust vault system ready for a production environment.

### Objectives and Implemented Improvements

The main objective is to apply advanced Solidity, security, and architectural techniques to transform the base contract. The key improvements implemented, in line with the course objectives, are:

- **Multi-token Support:** The contract was extended to accept deposits and withdrawals for both native ETH and multiple ERC-20 tokens.
- **Access Control:** Implemented OpenZeppelin's `AccessControl` to manage roles (e.g., `ROLE_ADMIN`) that restrict critical administrative functions.
- **Oracle Integration (Chainlink):** Utilizes Chainlink Data Feeds to fetch real-time prices and convert balances to an equivalent USD value.
- **USD Accounting and Global Cap:** The contract maintains internal accounting in USD (with 6 decimals, USDC-style) and enforces a global deposit limit (`bankCapUsd`) based on this value.
- **Security and Efficiency (Patterns):** Applied secure design patterns like Checks-Effects-Interactions (CEI), `SafeERC20` for transfers, and optimized gas usage (e.g., `unchecked`, custom errors).

---

## ✨ Design Decisions and Trade-offs

- **Access Control (`AccessControl`):** `AccessControl` was chosen over a simple `Ownable` for its flexibility in adding new roles in the future.
- **Internal Accounting:** Uses `address(0)` (the `NATIVE_TOKEN` constant) to represent ETH within the balance mappings, which is a standard convention.
- **Custom Errors:** All `require()` statements were migrated to custom errors (e.g., `BankCapExceeded`, `InsufficientFunds`, `FeedNotSet`). This significantly reduces gas costs for deployment and for failed transactions.
- **Decimal Conversion:** Implemented internal logic (`_amountTokenToUsd6`) to normalize all values. This function handles the varying decimals of ERC-20 tokens (e.g., 18, 8, 6) and Chainlink feed decimals (e.g., 8) to convert them to a single 6-decimal standard (`USD_DECIMALS`).
- **CEI Pattern:** All withdrawal functions (`withdrawETH`, `withdrawERC20`) strictly follow the Checks-Effects-Interactions pattern. The state (balances) is updated _before_ the external transfer to prevent re-entrancy attacks.

---

## 📂 Repository Structure

The repository follows the structure requested for the assignment deliverable:

KipuBankV2/ │ ├── src/ │ ├── KipuBankV2.sol # Main contract │ └── interfaces/ │ ├── IKipuBankV2.sol # Public interface │ └── IAggregatorV3Interface.sol # Chainlink interface │ ├── README.md # This documentation └── LICENSE # MIT License

---

## ⚙️ Deployment and Interaction Instructions

### Requirements

- Solidity `^0.8.28`
- Remix IDE or a local environment (Hardhat/Foundry)
- MetaMask connected to a Testnet (e.g., Sepolia)

### Deployment Steps (Remix IDE)

1.  Open [Remix IDE](https://remix.ethereum.org).
2.  Load the files from the `src/` folder into the file explorer.
3.  Compile `KipuBankV2.sol` (version `0.8.28`).
4.  In the "Deploy & Run" tab:
    - Environment: **Injected Provider (MetaMask)**.
    - Network: Sepolia Testnet.
    - Constructor Parameters:
      - `_admin`: Your wallet address.
      - `_withdrawalThresholdWei`: Withdrawal limit in Wei (e.g., `1000000000000000000` for 1 ETH).
      - `_bankCapUsd6`: Global cap in USD 6-decimals (e.g., `100000000000` for 100,000 USD).
      - `_ethUsdFeed`: Chainlink ETH/USD feed address (Sepolia: `0x694AA1769357215DE4FAC081bf1f309aDC325306`).
5.  Click **Deploy** and confirm in MetaMask.
6.  Verify the contract on Etherscan.

### Interaction Examples

**1. Deposit ETH**

```solidity
// Send ETH (e.g., 0.1 ETH) along with the function call:
depositETH() payable

2. Deposit ERC-20 (e.g., a stablecoin)

// 1. Approve the KipuBankV2 contract
ERC20(token_address).approve(kipubank_address, amount)

// 2. Call the deposit function
depositERC20(token_address, amount)

3. Register a new Token (Admin)

// (Requires ROLE_ADMIN)
// Example for registering a hypothetical "DAI" token
registerToken(
    "0xDAI_TOKEN_ADDRESS",
    "0xDAI_USD_FEED_ADDRESS",
    18 // Decimals of the DAI token
)
```
