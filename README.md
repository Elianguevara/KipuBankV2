# 🏦 KipuBankV2

> Multi-token vault with ETH and ERC-20 support, access control, and global USD cap.

## 📑 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Architecture](#-architecture)
- [Installation](#-installation)
- [Usage](#-usage)
- [Security](#-security)

## 📝 Overview

KipuBankV2 is a blockchain vault that enables:

- ETH and ERC-20 token deposits/withdrawals
- Automatic USD conversion using Chainlink
- Role-based access control
- Global deposit limit in USD

## 🔥 Features

- **Multi-token**: Native support for ETH and ERC-20 tokens
- **Oracle**: Chainlink integration for real-time pricing
- **Roles**: Permission system with `AccessControl`
- **Security**: CEI pattern, SafeERC20, and custom errors
- **Gas**: Optimizations with `unchecked` and custom errors

## 🏗 Architecture

```
contracts/
├── KipuBankV2.sol      # Main contract
└── interfaces/
    ├── IKipuBankV2.sol           # Public interface
    └── IAggregatorV3Interface.sol # Chainlink interface
```

## 🚀 Installation

1. Clone the repository:

```bash
git clone https://github.com/your-username/kipubankv2.git
cd kipubankv2
```

2. Install dependencies:

```bash
npm install
```

## 💻 Usage

### Deployment

```solidity
constructor(
    address _admin,                // Initial administrator
    uint256 _withdrawalThresholdWei, // ETH withdrawal limit (e.g., 1 ETH = 1e18)
    uint256 _bankCapUsd6,         // Global USD limit (6 decimals)
    address _ethUsdFeed          // Chainlink ETH/USD feed
)
```

### Main Functions

1. **ETH Deposits**

```solidity
// Send ETH with the call
function depositETH() external payable;
```

2. **ERC-20 Deposits**

```solidity
// First approve spending
IERC20(token).approve(kipubank, amount);
// Then deposit
function depositERC20(address token, uint256 amount) external;
```

3. **Withdrawals**

```solidity
function withdrawETH(uint256 amount) external;
function withdrawERC20(address token, uint256 amount) external;
```

### Admin Functions

```solidity
// Register new token (requires ROLE_ADMIN)
function registerToken(
    address token,   // Token address
    address feed,    // Chainlink price feed
    uint8 decimals  // Token decimals
) external;
```

## 🔒 Security Features

- CEI pattern implementation
- Reentrancy protection
- SafeERC20 for secure transfers
- Granular role control
- Comprehensive testing suite
- Custom error handling
- Withdrawal limits
- Global deposit cap

## 🛠 Technical Specifications

- Solidity Version: `^0.8.28`
- OpenZeppelin Dependencies:
  - AccessControl
  - SafeERC20
- Chainlink Price Feeds
- Gas Optimizations

## 📄 License

MIT License - See [LICENSE](./LICENSE) for details.
