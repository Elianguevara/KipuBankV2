# KipuBankV2 🏦

> Multi-token vault supporting ETH and ERC-20 with role-based access control, Chainlink price feeds, and USD-based capacity management.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.28-blue)](https://soliditylang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 📋 Tabla de Contenidos

- [Descripción](#-descripción)
- [Mejoras Implementadas](#-mejoras-implementadas)
- [Arquitectura del Contrato](#-arquitectura-del-contrato)
- [Requisitos Previos](#-requisitos-previos)
- [Instalación](#-instalación)
- [Despliegue](#-despliegue)
- [Interacción](#-interacción)
- [Decisiones de Diseño](#-decisiones-de-diseño)
- [Seguridad](#-seguridad)
- [Testing](#-testing)
- [Licencia](#-licencia)

---

## 🎯 Descripción

**KipuBankV2** es una evolución del contrato original KipuBank que implementa un sistema de bóveda multi-token con las siguientes capacidades:

- **Depósitos y retiros** de ETH y tokens ERC-20
- **Control de acceso** basado en roles (AccessControl de OpenZeppelin)
- **Límite global** del banco expresado en USD (6 decimales, estilo USDC)
- **Integración con oráculos de Chainlink** para conversión de precios en tiempo real
- **Optimización de gas** mediante patrones CEI, variables `immutable`/`constant` y accesos únicos a storage
- **Gestión robusta de errores** con custom errors

---

## ✨ Mejoras Implementadas

### 1. **Control de Acceso (AccessControl)**

- Implementación del patrón **AccessControl** de OpenZeppelin
- Rol `ROLE_ADMIN` para funciones administrativas (registro de tokens, actualización de feeds)
- Separación clara entre operaciones de usuarios y administradores

**Justificación**: Permite administración descentralizada y escalabilidad del contrato sin comprometer la seguridad.

---

### 2. **Soporte Multi-Token**

- Soporte nativo para **ETH** (representado como `address(0)`)
- Registro dinámico de **tokens ERC-20** con sus respectivos:
  - Price feeds de Chainlink
  - Decimales del token
- Contabilidad separada por token y usuario mediante mappings anidados

**Justificación**: Flexibilidad para expandir el ecosistema del banco sin redesplegar el contrato.

---

### 3. **Contabilidad Global en USD**

- Variable `totalUsdLocked` que rastrea el valor total en USD-6
- Límite configurable `bankCapUsd` para controlar la exposición del banco
- Conversión automática de tokens a USD usando Chainlink

**Justificación**: Permite gestión unificada de riesgo independientemente de la volatilidad de activos individuales.

---

### 4. **Integración con Chainlink Oracles**

- Función interna `_amountTokenToUsd6()` para conversión de precios
- Manejo robusto de diferentes decimales entre tokens y feeds
- Validación de precios (revert si `price <= 0`)

**Justificación**: Datos de precios confiables y descentralizados, esenciales para DeFi.

---

### 5. **Optimización de Gas y Seguridad**

#### ✅ Layout del Código Estrictamente Ordenado

````

#### ✅ Verificación Única de Desborde
```solidity
// ❌ ANTES: Solidity verifica 2 veces
unchecked {
    balances[token][user] -= amount; // aún verifica underflow
}

// ✅ AHORA: Verificamos manualmente, luego unchecked real
uint256 userBalance = balances[token][user];
if (amount > userBalance) revert InsufficientFunds(userBalance);
unchecked {
    userBalance -= amount; // sin verificación redundante
}
````

#### ✅ Modifiers Simples y Modulares

```solidity
// ❌ ANTES: Modifier que accede a storage
modifier validWithdrawal(address token, uint256 amount) {
    uint256 bal = balances[token][msg.sender]; // ❌ acceso a storage
    if (amount > bal) revert InsufficientFunds(bal);
    _;
}

// ✅ AHORA: Modifiers sin lógica de storage
modifier validAmount(uint256 _amount) {
    if (_amount == 0) revert ZeroAmount();
    _;
}

modifier withinThreshold(uint256 _amount) {
    if (_amount > withdrawalThresholdNative) {
        revert WithdrawalThresholdExceeded(withdrawalThresholdNative);
    }
    _;
}
```

#### ✅ Patrón CEI (Checks-Effects-Interactions)

```solidity
function withdrawETH(uint256 _amount) external {
    // CHECKS
    if (_amount == 0) revert ZeroAmount();
    uint256 userBalance = balances[NATIVE_TOKEN][msg.sender];
    if (_amount > userBalance) revert InsufficientFunds(userBalance);

    // EFFECTS
    unchecked { userBalance -= _amount; }
    balances[NATIVE_TOKEN][msg.sender] = userBalance;
    totalUsdLocked -= usd6;

    // INTERACTIONS
    (bool ok, ) = msg.sender.call{value: _amount}("");
    if (!ok) revert TransferFailed();
}
```

**Justificación**: Reduce costos de gas significativamente y previene vulnerabilidades de reentrancia.

---

### 6. **Custom Errors y Eventos**

- **Errors**: `ZeroAmount`, `BankCapExceeded`, `InsufficientFunds`, `WithdrawalThresholdExceeded`, etc.
- **Events**: `Deposit`, `Withdrawal`, `TokenRegistered`, `PriceFeedUpdated`

**Justificación**: Custom errors ahorran ~50% de gas vs `require()` con strings. Los eventos permiten tracking off-chain.

---

## 🏗️ Arquitectura del Contrato

```
KipuBankV2
├── Control de Acceso
│   └── ROLE_ADMIN (registro de tokens, actualización de feeds)
├── Oráculos Chainlink
│   ├── priceFeeds[token] → IAggregatorV3Interface
│   └── _amountTokenToUsd6() (conversión interna)
├── Contabilidad Multi-Token
│   ├── balances[token][user]
│   ├── tokenDecimals[token]
│   └── totalUsdLocked (global USD-6)
└── Funciones Principales
    ├── depositETH() / depositERC20()
    ├── withdrawETH() / withdrawERC20()
    └── registerToken() / updateEthFeed()
```

---

## 📦 Requisitos Previos

- **Node.js** v18+ y **npm**
- **Foundry** (para compilación y despliegue)
  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```
- **Wallet** con fondos en testnet (Sepolia recomendado)

---

## 🚀 Instalación

```bash
# Clonar el repositorio
git clone https://github.com/tu-usuario/KipuBankV2.git
cd KipuBankV2

# Instalar dependencias de OpenZeppelin
forge install OpenZeppelin/openzeppelin-contracts

# Compilar
forge build
```

---

## 📡 Despliegue

### 1. Configurar Variables de Entorno

Crea un archivo `.env`:

```env
PRIVATE_KEY=tu_clave_privada
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/TU_API_KEY
ETHERSCAN_API_KEY=tu_etherscan_api_key
```

### 2. Obtener Direcciones de Price Feeds

Para Sepolia, usa los feeds oficiales de Chainlink:

- **ETH/USD**: `0x694AA1769357215DE4FAC081bf1f309aDC325306`
- **USDC/USD**: `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E`
- **LINK/USD**: `0xc59E3633BAAC79493d908e63626716e204A45EdF`

### 3. Desplegar el Contrato

```bash
forge create src/KipuBankV2.sol:KipuBankV2 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args \
    "0xTU_ADDRESS" \           # admin address
    "1000000000000000000" \   # 1 ETH withdrawal threshold
    "1000000000" \            # 1000 USD bank cap (6 decimals)
    "0x694AA1769357215DE4FAC081bf1f309aDC325306" # ETH/USD feed Sepolia
```

### 4. Verificar en Etherscan

```bash
forge verify-contract \
  --chain-id 11155111 \
  --num-of-optimizations 200 \
  --watch \
  --constructor-args $(cast abi-encode "constructor(address,uint256,uint256,address)" "0xTU_ADDRESS" "1000000000000000000" "1000000000" "0x694AA1769357215DE4FAC081bf1f309aDC325306") \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --compiler-version v0.8.28 \
  DIRECCION_DEL_CONTRATO \
  src/KipuBankV2.sol:KipuBankV2
```

---

## 🔧 Interacción

### Registrar un Token ERC-20

```solidity
// Desde una cuenta con ROLE_ADMIN
kipuBank.registerToken(
    0xTokenAddress,     // dirección del token
    0xFeedAddress,      // Chainlink feed
    6                   // decimales del token
);
```

### Depositar ETH

```solidity
// Cualquier usuario
kipuBank.depositETH{value: 0.1 ether}();
```

### Depositar Token ERC-20

```solidity
// 1. Aprobar primero
IERC20(tokenAddress).approve(address(kipuBank), amount);

// 2. Depositar
kipuBank.depositERC20(tokenAddress, amount);
```

### Retirar ETH

```solidity
kipuBank.withdrawETH(0.05 ether); // máximo según withdrawalThresholdNative
```

### Consultar Balance

```solidity
uint256 balance = kipuBank.getBalance(
    address(0),      // ETH (NATIVE_TOKEN)
    userAddress
);
```

---

## 🎨 Decisiones de Diseño

### 1. **¿Por qué USD-6 en lugar de USD-18?**

**Decisión**: Usar 6 decimales (estilo USDC) en lugar de 18.

**Razones**:

- Compatible con la mayoría de stablecoins (USDC, USDT)
- Reduce riesgo de overflow en multiplicaciones
- Suficiente precisión para valores monetarios (~$0.000001)

**Trade-off**: Menos precisión para micro-transacciones, pero irrelevante en este caso de uso.

---

### 2. **¿Por qué `immutable` para `withdrawalThresholdNative`?**

**Decisión**: Threshold fijo en deployment.

**Razones**:

- Ahorro de gas (sin SLOAD, compilado directamente)
- Previene cambios administrativos arbitrarios post-deployment
- Valor conocido de antemano

**Trade-off**: No se puede ajustar sin redespliegue. Alternativa: hacer `public` mutable con función admin, pero sacrifica gas y seguridad.

---

### 3. **¿Por qué `address(0)` para ETH?**

**Decisión**: Usar dirección cero como identificador de ETH.

**Razones**:

- Convención estándar en la industria (WETH, Uniswap, etc.)
- Permite arquitectura unificada con tokens ERC-20
- Simplifica mappings: `balances[address(0)][user]`

**Trade-off**: Ninguno significativo, es la práctica estándar.

---

### 4. **¿Por qué NO usar `ReentrancyGuard`?**

**Decisión**: Implementar CEI manualmente en lugar de usar OpenZeppelin's `ReentrancyGuard`.

**Razones**:

- CEI bien implementado hace innecesario el guard
- Ahorra ~2500 gas por transacción
- Evita dependencia adicional

**Trade-off**: Requiere disciplina en el orden de operaciones. Si se agregan funciones complejas futuras, considerar agregar el guard.

---

### 5. **¿Por qué mapear `tokenDecimals` en lugar de llamar `token.decimals()`?**

**Decisión**: Almacenar decimales en registro.

**Razones**:

- No todos los ERC-20 implementan `decimals()` (aunque es estándar)
- Evita `call` externo en cada conversión de precio
- Ahorra gas significativo en operaciones frecuentes

**Trade-off**: Requiere registro manual, pero solo se hace una vez por token.

---

## 🔒 Seguridad

### Auditorías Recomendadas

Antes de producción, este contrato debe ser auditado por:

- [ ] Auditoría interna del equipo
- [ ] Auditoría externa profesional
- [ ] Bug bounty program

### Consideraciones de Seguridad Implementadas

✅ **Reentrancy Protection**: Patrón CEI estricto  
✅ **Integer Overflow**: Verificaciones manuales + `unchecked` consciente  
✅ **Access Control**: Roles granulares con OpenZeppelin  
✅ **Oracle Manipulation**: Validación de precios (`price > 0`)  
✅ **Failed Transfers**: SafeERC20 para tokens, validación de `call()` para ETH  
✅ **Zero Address**: Validaciones en constructor y funciones admin

### Riesgos Conocidos

⚠️ **Oracle Dependency**: El contrato confía en Chainlink. Si un feed falla o es manipulado, afecta las conversiones.

**Mitigación**: Implementar timeouts de actualización y comparación de múltiples feeds en V3.

⚠️ **Bank Cap Global**: Si el cap es muy bajo, puede impedir depósitos legítimos.

**Mitigación**: Configurar cap generoso y monitorearlo activamente.

---

## 🧪 Testing

```bash
# Ejecutar tests
forge test

# Con verbosidad
forge test -vvv

# Test específico
forge test --match-test testDepositETH

# Coverage
forge coverage
```

### Casos de Test Recomendados

- ✅ Depósito ETH exitoso
- ✅ Depósito ERC-20 exitoso
- ✅ Retiro dentro del threshold
- ✅ Revert: retiro excede threshold
- ✅ Revert: fondos insuficientes
- ✅ Revert: bank cap excedido
- ✅ Conversión USD correcta con diferentes decimales
- ✅ Solo admin puede registrar tokens
- ✅ Revert: precio inválido del oracle

---

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver archivo `LICENSE` para más detalles.

---

## 👨‍💻 Autor

**Victor Elian Guevara**  
Trabajo Final Módulo 3 - Ethereum Developer Program

---

## 📚 Referencias

- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Chainlink Data Feeds](https://docs.chain.link/data-feeds)
- [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- [Foundry Book](https://book.getfoundry.sh/)

---

## 🔄 Roadmap V3

- [ ] Implementar staking rewards
- [ ] Multi-oracle aggregation (Chainlink + Uniswap TWAP)
- [ ] Límites por token además del cap global
- [ ] Sistema de fees dinámicos
- [ ] Integración con lending protocolssolidity

1. Imports
2. Control de Acceso (roles)
3. Declaraciones de Tipos (errors, events)
4. Instancias de Oráculos (mappings de price feeds)
5. Variables Constant & Immutable
6. Mappings de Estado
7. Constructor
8. Modifiers
9. Funciones (Admin → Deposit → Withdraw → View → Internal)

````

#### ✅ Accesos Únicos a Storage
```solidity
// ❌ ANTES: Múltiples accesos
balances[token][user] -= amount; // lectura implícita + escritura

// ✅ AHORA: 1 lectura + 1 escritura
uint256 userBalance = balances[token][user]; // 1 lectura
unchecked { userBalance -= amount; }
balances[token][user] = userBalance; // 1 escritura
````
