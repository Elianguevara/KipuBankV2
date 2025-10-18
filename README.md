# 🏦 KipuBankV2

> Vault multi-token con soporte para ETH y ERC-20, control de acceso basado en roles y límite global en USD.

## 📑 Tabla de Contenidos

- [Visión General](#-visión-general)
- [Mejoras Implementadas](#-mejoras-implementadas)
- [Arquitectura](#-arquitectura)
- [Instalación](#-instalación)
- [Despliegue](#-despliegue)
- [Uso](#-uso)
- [Decisiones de Diseño](#-decisiones-de-diseño)
- [Seguridad](#-seguridad)
- [Licencia](#-licencia)

## 📝 Visión General

KipuBankV2 es una evolución significativa del contrato original KipuBank, transformándolo en un vault multi-token de nivel producción. El contrato permite:

- Depósitos y retiros de ETH y tokens ERC-20
- Conversión automática a USD utilizando oráculos de Chainlink
- Control de acceso basado en roles con OpenZeppelin AccessControl
- Límite de capacidad global expresado en USD
- Contabilidad interna con decimales normalizados a 6 (estilo USDC)

Este proyecto representa una implementación completa de patrones avanzados de Solidity, integrando seguridad, eficiencia de gas y arquitectura escalable.

## 🚀 Mejoras Implementadas

### 1. **Control de Acceso Basado en Roles**

Implementación de `AccessControl` de OpenZeppelin para gestión segura de permisos:

```solidity
bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
```

- Separación clara entre usuarios regulares y administradores
- Funciones administrativas protegidas (registro de tokens, actualización de feeds)
- Modifier personalizado `onlyBankAdmin` para validación de permisos

### 2. **Soporte Multi-Token**

Expansión completa para soportar múltiples activos:

- **ETH nativo**: Representado como `address(0)` (NATIVE_TOKEN)
- **Tokens ERC-20**: Soporte para cualquier token ERC-20 registrado
- **Mappings anidados**: `mapping(address => mapping(address => uint256))` para contabilidad por token y usuario
- **Registry de decimales**: Almacenamiento de decimales por token para conversiones precisas

### 3. **Integración de Oráculos Chainlink**

Uso de Data Feeds para pricing en tiempo real:

```solidity
mapping(address => IAggregatorV3Interface) private priceFeeds;
```

- Conversión automática de valores de tokens a USD
- Soporte para feeds de diferentes decimales (típicamente 8 para USD pairs)
- Validación de precios (rechaza precios <= 0)
- Actualización dinámica de feeds por administradores

### 4. **Sistema de Conversión de Decimales**

Función interna robusta para normalización a USD-6:

```solidity
function _amountTokenToUsd6(address _token, uint256 _amount) private view returns (uint256 usd6)
```

**Lógica implementada:**

- Manejo de diferentes decimales de token (ETH=18, USDC=6, WBTC=8, etc.)
- Manejo de diferentes decimales de feed (8 para USD, 18 para ETH, etc.)
- Conversión precisa sin pérdida de precisión significativa
- Fórmula: `usd6 = (amount * price) / 10^(tokenDecimals + feedDecimals - 6)`

### 5. **Bank Cap Global en USD**

Límite de capacidad total expresado en términos de USD:

```solidity
uint256 public immutable bankCapUsd;
uint256 public totalUsdLocked;
```

- Validación en cada depósito contra el cap global
- Tracking en tiempo real del valor total bloqueado
- Error específico con capacidad disponible: `BankCapExceeded(uint256 availableUsd6)`

### 6. **Seguridad y Patrones Avanzados**

**Checks-Effects-Interactions (CEI):**

```solidity
// 1. Checks
if (msg.value == 0) revert ZeroAmount();
if (newTotal > bankCapUsd) revert BankCapExceeded(...);

// 2. Effects
balances[NATIVE_TOKEN][msg.sender] += msg.value;
totalUsdLocked = newTotal;

// 3. Interactions
emit Deposit(...);
```

**Optimizaciones de gas:**

- `unchecked` blocks para operaciones seguras (incrementos post-validación)
- Variables `immutable` para valores de construcción
- Variables `constant` para valores fijos
- Custom errors en lugar de strings (ahorra ~50% de gas)

**SafeERC20:**

- Protección contra tokens no estándar
- Manejo seguro de `transferFrom` y `transfer`
- Compatibilidad con tokens que no devuelven booleanos

### 7. **Eventos y Observabilidad**

Sistema completo de eventos para tracking on-chain:

```solidity
event Deposit(address indexed token, address indexed user, uint256 amountToken, uint256 amountUsd6);
event Withdrawal(address indexed token, address indexed user, uint256 amountToken, uint256 amountUsd6);
event TokenRegistered(address indexed token, uint8 decimals, address indexed feed);
event PriceFeedUpdated(address indexed token, address indexed feed);
```

### 8. **Manejo de Errores Personalizado**

Errores específicos con parámetros informativos:

```solidity
error BankCapExceeded(uint256 availableUsd6);
error InsufficientFunds(uint256 balanceToken);
error WithdrawalThresholdExceeded(uint256 thresholdWei);
error FeedNotSet(address token);
```

## 🏗 Arquitectura

```
KipuBankV2/
├── src/
│   └── contracts/
│       ├── KipuBankV2.sol              # Contrato principal
│       └── interfaces/
│           ├── IKipuBankV2.sol         # Interfaz pública
│           └── IAggregatorV3Interface.sol  # Interfaz Chainlink
├── README.md
└── LICENSE
```

### Estructura del Contrato

**Imports:**

- OpenZeppelin: `AccessControl`, `IERC20`, `SafeERC20`
- Chainlink: `IAggregatorV3Interface`

**Storage:**

- `totalUsdLocked`: Contabilidad global en USD-6
- `balances`: Mapping anidado [token][user] → amount
- `priceFeeds`: Registry de oráculos Chainlink
- `tokenDecimals`: Registry de decimales por token
- Contadores: `depositCount`, `withdrawalCount`

## 🛠 Instalación

1. **Clonar el repositorio:**

```bash
git clone https://github.com/Elianguevara/KipuBankV2.git
cd KipuBankV2
```

2. **Instalar dependencias:**

```bash
npm install
# o
yarn install
```

**Dependencias requeridas:**

- `@openzeppelin/contracts@^5.0.0`
- Compilador Solidity `^0.8.28`

## 🚀 Despliegue

### Parámetros del Constructor

```solidity
constructor(
    address _admin,                    // Dirección del administrador inicial
    uint256 _withdrawalThresholdWei,  // Límite de retiro de ETH (ej: 1 ETH = 1e18)
    uint256 _bankCapUsd6,             // Límite global en USD con 6 decimales
    address _ethUsdFeed               // Feed de Chainlink ETH/USD
)
```

### Ejemplo de Despliegue (Sepolia)

```javascript
// Usando Hardhat
const KipuBankV2 = await ethers.getContractFactory("KipuBankV2");
const bank = await KipuBankV2.deploy(
  "0xYourAdminAddress", // Admin
  ethers.parseEther("1"), // 1 ETH withdrawal limit
  1000000n * 10n ** 6n, // 1M USD cap (6 decimals)
  "0x694AA1769357215DE4FAC081bf1f309aDC325306" // ETH/USD feed Sepolia
);
```

### Feeds de Chainlink por Red

**Sepolia:**

- ETH/USD: `0x694AA1769357215DE4FAC081bf1f309aDC325306`

**Mainnet:**

- ETH/USD: `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`
- USDC/USD: `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6`

### Verificación en Block Explorer

```bash
npx hardhat verify --network sepolia DEPLOYED_ADDRESS "ADMIN_ADDRESS" "THRESHOLD" "CAP" "ETH_FEED"
```

## 💻 Uso

### 1. Depósito de ETH

```solidity
// Enviar ETH directamente con la llamada
kipuBank.depositETH{value: 0.5 ether}();
```

### 2. Registro de Token ERC-20 (Admin)

```solidity
// Solo ROLE_ADMIN puede ejecutar
kipuBank.registerToken(
    0x...,  // Dirección del token (ej: USDC)
    0x...,  // Feed de Chainlink para TOKEN/USD
    6       // Decimales del token
);
```

### 3. Depósito de ERC-20

```solidity
// Paso 1: Aprobar gasto
IERC20(tokenAddress).approve(kipuBankAddress, amount);

// Paso 2: Depositar
kipuBank.depositERC20(tokenAddress, amount);
```

### 4. Retiros

```solidity
// Retirar ETH (sujeto a withdrawalThresholdNative)
kipuBank.withdrawETH(0.3 ether);

// Retirar ERC-20
kipuBank.withdrawERC20(tokenAddress, amount);
```

### 5. Consultas

```solidity
// Balance de un usuario para un token específico
uint256 balance = kipuBank.getBalance(tokenAddress, userAddress);

// Información del feed de un token
address feed = kipuBank.getFeed(tokenAddress);

// Decimales registrados de un token
uint8 decimals = kipuBank.getTokenDecimals(tokenAddress);

// Estado global
uint256 tvl = kipuBank.totalUsdLocked();
uint256 cap = kipuBank.bankCapUsd();
```

## 🎯 Decisiones de Diseño

### 1. **Uso de `address(0)` para ETH**

**Decisión:** Representar ETH nativo como `NATIVE_TOKEN = address(0)`.

**Razones:**

- Unifica la lógica de contabilidad multi-token
- Permite usar la misma estructura de mappings para ETH y ERC-20
- Convención ampliamente adoptada en DeFi (Uniswap, Aave)
- Simplicidad en queries y eventos

**Trade-off:** Requiere chequeos explícitos `_token == NATIVE_TOKEN` en algunas funciones.

### 2. **USD con 6 Decimales**

**Decisión:** Normalizar toda la contabilidad interna a 6 decimales (como USDC).

**Razones:**

- Estándar de facto en DeFi para stablecoins
- Balance entre precisión y eficiencia de gas
- Facilita integración futura con protocolos DeFi
- Reduce riesgo de overflow en cálculos

**Trade-off:** Conversiones de decimales necesarias en cada operación.

### 3. **Withdrawal Threshold Solo para ETH**

**Decisión:** Aplicar límite de retiro solo a ETH nativo, no a ERC-20.

**Razones:**

- ETH es el activo más líquido y volátil
- Protección adicional contra drenado rápido de liquidez nativa
- Flexibilidad para tokens con diferentes casos de uso
- Simplicidad de implementación

**Trade-off:** Protección asimétrica entre activos.

### 4. **Immutable vs Constant**

**Decisión:**

- `constant` para: ROLE_ADMIN, NATIVE_TOKEN, USD_DECIMALS
- `immutable` para: withdrawalThresholdNative, bankCapUsd

**Razones:**

- `constant`: Valores conocidos en compile-time, menor gas
- `immutable`: Valores configurables en constructor, flexibilidad de despliegue
- Ambos previenen modificaciones post-despliegue

### 5. **AccessControl vs Ownable**

**Decisión:** Usar `AccessControl` de OpenZeppelin.

**Razones:**

- Mayor granularidad de permisos
- Escalabilidad: múltiples admins, múltiples roles futuros
- Patrón estándar en contratos empresariales
- Facilita auditoría de permisos

**Trade-off:** Overhead de gas ligeramente mayor que Ownable simple.

### 6. **CEI Pattern Estricto**

**Decisión:** Implementar Checks-Effects-Interactions en todas las funciones de estado.

**Razones:**

- Prevención de reentrancy sin necesidad de ReentrancyGuard
- Claridad de código y facilidad de auditoría
- Menor consumo de gas vs usar modifier adicional
- Best practice de Solidity

### 7. **Custom Errors con Parámetros**

**Decisión:** Reemplazar `require(condition, "string")` por custom errors.

**Razones:**

- Ahorro de gas: ~50% menos que strings en reverts
- Información contextual mediante parámetros
- Mejor integración con herramientas de desarrollo
- Mejora UX: mensajes más descriptivos

### 8. **No Usar ReentrancyGuard**

**Decisión:** No incluir `ReentrancyGuard` de OpenZeppelin.

**Razones:**

- CEI pattern proporciona protección suficiente
- Ahorro de gas (~20k por transacción)
- Storage slots más eficientes
- Complejidad reducida

**Trade-off:** Requiere vigilancia continua en futuras modificaciones.

## 🔒 Seguridad

### Medidas Implementadas

1. **Protección contra Reentrancy**

   - Patrón CEI estrictamente aplicado
   - State updates antes de external calls

2. **Safe Transfers**

   - `SafeERC20` para todas las operaciones ERC-20
   - Validación de retorno de ETH transfers

3. **Access Control**

   - Funciones administrativas protegidas
   - Validación de roles en modifiers

4. **Input Validation**

   - Chequeos de zero amount
   - Validación de addresses
   - Verificación de precios de oráculos

5. **Integer Overflow Protection**

   - Solidity ^0.8.28 con chequeos automáticos
   - `unchecked` solo en bloques post-validación

6. **Oracle Manipulation Resistance**
   - Validación de precios positivos
   - Uso de feeds de Chainlink auditados

### Vulnerabilidades Mitigadas

| Vulnerabilidad          | Mitigación                                              |
| ----------------------- | ------------------------------------------------------- |
| Reentrancy              | CEI Pattern                                             |
| Integer Overflow        | Solidity 0.8+                                           |
| Token Transfer Failures | SafeERC20                                               |
| Access Control Bypass   | AccessControl + modifiers                               |
| Oracle Manipulation     | Price validation                                        |
| Front-running           | Design inherente (no precios manipulables por usuarios) |

### Consideraciones Adicionales

- **Pausabilidad**: No implementada. Considerar `Pausable` para producción.
- **Upgrade Pattern**: Contrato no upgradeable por diseño (transparencia).
- **Rate Limiting**: Withdrawal threshold para ETH. Considerar rate limiting adicional.
- **Emergency Withdrawal**: No implementada. Considerar para casos extremos.

## 📊 Gas Optimizations

- **Custom Errors**: ~50% reducción vs require strings
- **Unchecked Blocks**: Ahorro en incrementos seguros
- **Immutable/Constant**: Lectura directa sin SLOAD
- **Indexed Events**: Búsqueda eficiente on-chain
- **Short-circuit Evaluations**: En validaciones complejas

## 🧪 Testing

Recomendaciones para suite de tests completa:

```solidity
// Unit Tests
- depositETH: success, zero amount, cap exceeded
- depositERC20: success, unregistered token, approval handling
- withdrawETH: success, insufficient balance, threshold exceeded
- withdrawERC20: success, invalid token
- registerToken: success, unauthorized, zero address
- USD conversion: various decimals, edge cases

// Integration Tests
- Multi-user scenarios
- Multi-token scenarios
- Oracle price changes
- Role management flows

// Fuzz Tests
- Random amounts and tokens
- Edge values (MAX_UINT256, etc.)
```

## 📄 Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver el archivo [LICENSE](./LICENSE) para más detalles.

---

**Autor:** Victor Elian Guevara  
**Versión:** 2.0.0  
**Solidity:** ^0.8.28  
**Red Recomendada:** Sepolia Testnet

Para preguntas o contribuciones, por favor abre un issue en GitHub.
