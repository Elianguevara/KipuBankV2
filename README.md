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

