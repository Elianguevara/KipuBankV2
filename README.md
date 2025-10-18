# KipuBankV2

## 📌 Overview

KipuBankV2 is the **evolution of the original KipuBank contract**.  
It has been refactored and extended to simulate a **production-ready vault system**, following **best practices in Solidity, security, and architecture**.  

The contract supports:
- Deposits and withdrawals of **ETH** and **ERC-20 tokens**.
- **Access control** using OpenZeppelin’s `AccessControl`.
- **Chainlink price feeds** to calculate the value of assets in USD (6 decimals, USDC-style).
- A **global bank cap** expressed in USD-6.
- **Withdrawal thresholds** per transaction.
- **Gas-optimized accounting** with custom errors, events, and CEI pattern.

This project demonstrates how to **refactor, scale, and secure** a smart contract for real-world scenarios.

---

## 🎯 Objectives of the Project

- Identify and address **limitations** in the original `KipuBank`.
- Apply **advanced Solidity resources** and secure design patterns.
- Introduce **new features** relevant to production (multi-token, USD cap, oracles).
- Follow **good practices** for code structure, documentation, and deployment.
- Present a clear and professional repository simulating open-source collaboration.

---

## ✨ Key Features

- ✅ **Multi-token vault**: ETH + registered ERC-20 tokens.  
- ✅ **Role-based access control** (`ROLE_ADMIN`).  
- ✅ **Global capacity cap** enforced in **USD-6**.  
- ✅ **Chainlink price oracles** for real-time USD conversion.  
- ✅ **Decimal conversion logic** (ERC-20 decimals + price feed decimals → USDC decimals).  
- ✅ **Custom errors** for cheaper reverts and clearer debugging.  
- ✅ **Gas efficiency**: single storage reads/writes, `unchecked` increments.  
- ✅ **Events** for deposits, withdrawals, and token/price feed updates.  
- ✅ **SafeERC20** wrapper for ERC-20 transfers.  
- ✅ Strict use of **Checks-Effects-Interactions (CEI)** pattern.  

---


## 📂 Repository Structure

KipuBankV2/
│── contracts/
│ ├── KipuBankV2.sol # Main smart contract
│ └── interfaces/
│ ├── IKipuBankV2.sol # Public interface for integration
│ └── IAggregatorV3Interface.sol # Minimal Chainlink interface
│
│── README.md # Project documentation
│── LICENSE # MIT License


---

## ⚙️ Deployment Instructions

### 🔧 Requirements
- Solidity `^0.8.28`
- Remix IDE or Hardhat environment
- MetaMask connected to a public testnet (Sepolia recommended)
- Chainlink price feed addresses for ETH and ERC-20 tokens

### 🚀 Steps (Remix IDE)

1. Go to [Remix IDE](https://remix.ethereum.org).  
2. Create a new workspace and add the `contracts/` folder.  
3. Compile `KipuBankV2.sol` with Solidity version `0.8.28`.  
4. In **Deploy & Run Transactions**:
   - Select **Injected Provider (MetaMask)**.  
   - Network: Sepolia Testnet.  
   - Constructor parameters:
     - `_admin`: Your wallet address.  
     - `_withdrawalThresholdWei`: e.g. `1000000000000000000` (1 ETH).  
     - `_bankCapUsd6`: e.g. `100000000000` (100,000 USDC in 6 decimals).  
     - `_ethUsdFeed`: Chainlink ETH/USD feed (Sepolia: `0x694AA1769357215DE4FAC081bf1f309aDC325306`).  
5. Click **Deploy** and confirm transaction in MetaMask.  
6. Verify contract in [Etherscan](https://sepolia.etherscan.io/) by publishing the source code.  

---

## 🧪 Interaction Examples

### Deposit ETH
```solidity
depositETH() payable

Send ETH along with the transaction.

Deposit ERC-20

Approve allowance:
ERC20.approve(KipuBankV2_address, amount)
