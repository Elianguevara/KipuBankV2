# 🏦 KipuBankV2

## ✨ High-level Improvements

KipuBankV2 is an evolution of the original **KipuBank** smart contract.  
The improvements focus on **security**, **multi-token support**, **unified accounting**, and **gas efficiency**, making the contract closer to a production-ready design.

### 🔒 Security

- Role-based access control with OpenZeppelin `AccessControl`.
- `Pausable` to stop deposits/withdrawals in case of emergency.
- `ReentrancyGuard` to prevent reentrancy attacks.
- Custom errors instead of `require` strings (more gas efficient).

### 💱 Multi-token Support

- ETH deposits converted into USD-6 using Chainlink price feeds.
- USDC deposits handled 1:1 with USD-6.
- Withdrawals in ETH or USDC.

### 📊 Unified Accounting

- Internal ledger in USD-6 (6 decimals).
- Nested mapping `s_balances[user][token]`.
- `address(0)` = ETH, `address(USDC)` = USDC.

### 🔗 Oracle Integration

- Chainlink ETH/USD price feed.
- Staleness & compromised data checks.

### ⚡ Gas Efficiency

- Reduced storage reads/writes.
- Use of `immutable` and `constant`.
- Strict **Checks-Effects-Interactions** pattern.

---

## 🚀 Deployment Instructions

### 📋 Requirements

- **Remix IDE** or Hardhat/Foundry.
- **MetaMask** connected to **Sepolia Testnet**.
- Testnet ETH (from [Sepolia faucet](https://sepoliafaucet.com/)).

### 🛠️ Steps (Remix + MetaMask)

1. Open [Remix IDE](https://remix.ethereum.org).
2. Load `KipuBankV2.sol` into workspace.
3. Compile:
   - Solidity version **0.8.26**
   - Optimization **200 runs**
4. Deploy:
   - Env: **Injected Provider - MetaMask**
   - Contract: `KipuBankV2`
   - Constructor args (example):

| Param                     | Value                                        |
| ------------------------- | -------------------------------------------- |
| `admin`                   | `0xYourAddress`                              |
| `usdc`                    | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| `ethUsdFeed`              | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |
| `bankCapUSD6`             | `1000000000000` (1M USD-6)                   |
| `withdrawalThresholdUSD6` | `10000000000` (10k USD-6)                    |

5. Confirm in MetaMask.
6. Verify contract on **Sepolia Etherscan**:
   - Compiler: `0.8.26`, opt: 200 runs.
   - Paste source code.
   - Provide ABI-encoded constructor args.

---

## 🎮 Interaction Guide

Once verified, interact via **Etherscan UI**:  
👉 [Sepolia Etherscan Example](https://sepolia.etherscan.io)

### 📖 Read-only (Free)

- `getBalanceUSD6(user, token)` → User balance.
- `getTotalBalanceUSD6(user)` → User total balance.
- `getETHPrice()` → ETH/USD price.
- `previewETHToUSD6(weiAmount)` → Simulate ETH → USD-6.
- `previewUSD6ToETH(usd6Amount)` → Simulate USD-6 → ETH.

### ✍️ State-changing (Gas required)

1. **Deposit ETH**

   - `depositETH()` + enter ETH value.

2. **Deposit USDC**

   - `approve` USDC first.
   - Then call `depositUSDC(amount)`.

3. **Withdraw ETH**

   - `withdrawETH(usd6Amount)`.

4. **Withdraw USDC**

   - `withdrawUSDC(usd6Amount)`.

5. **Admin Controls**
   - `pause()` / `unpause()` → Emergency stop.
   - `rescue(token, amount)` → Recover extra funds.

---

## 🔑 Roles & Access Control

KipuBankV2 uses OpenZeppelin **AccessControl** to manage permissions securely.

### Roles Defined

- **DEFAULT_ADMIN_ROLE**

  - Assigned to the `admin` address at deployment.
  - Can grant/revoke roles.
  - Can update global bank capacity (`setBankCapUSD6`).

- **PAUSER_ROLE**

  - Can call `pause()` and `unpause()`.
  - Used to freeze operations in emergencies.

- **TREASURER_ROLE**
  - Can call `rescue(token, amount)` to recover ERC20 or ETH mistakenly sent to the contract.
  - Does not modify user balances in the ledger.

### Managing Roles

- `grantRole(bytes32 role, address account)` → assign role.
- `revokeRole(bytes32 role, address account)` → remove role.
- `hasRole(bytes32 role, address account)` → check role.

The contract exposes these identifiers:

- `PAUSER_ROLE`
- `TREASURER_ROLE`

---

## 🧠 Design Decisions & Trade-offs

- ✅ **Unified USD-6 ledger** → Simplifies multi-asset tracking, but depends on Chainlink.
- ✅ **Role-based access** → Secure & modular, but requires proper setup.
- ✅ **Chainlink oracle** → Reliable pricing, but external dependency.
- ✅ **Gas optimization** → Cheaper execution, but slightly harder readability.
- ✅ **Custom errors** → Gas-efficient, but less verbose for end-users.
