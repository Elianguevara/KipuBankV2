# 🏦 KipuBankV3

KipuBankV3 es la evolución del banco unificado en USD construido en el módulo anterior. Mantiene el modelo de seguridad de KipuBankV2 (roles, `Pausable`, `ReentrancyGuard`) y agrega integración con Uniswap V2 para aceptar cualquier token con par directo a USDC. Todos los depósitos terminan denominados en USDC dentro del libro contable interno, lo que permite que los retiros se realicen en USDC o se ruteen a ETH nuevamente.

## ✨ Novedades principales

| Tema | KipuBankV2 | KipuBankV3 |
| --- | --- | --- |
| Tokens soportados | ETH (vía Chainlink) y USDC | ETH, USDC y cualquier ERC20 con par directo en Uniswap V2 |
| Conversión | Chainlink fija para ETH | Swaps enrutados a USDC usando Uniswap V2 |
| Retiro en ETH | Conversión con oráculo | Swap USDC → ETH en Uniswap V2 con control de `minOut` |
| Prevención de reentradas | `ReentrancyGuard` | Igual que V2 |
| Gobernanza | `AccessControl` (`DEFAULT_ADMIN`, `PAUSER`, `TREASURER`) | Igual que V2 |
| Límite global (`bankCap`) | Se aplica a depósitos de ETH/USDC | Se aplica antes y después de cada swap para cualquier activo |

### Flujo de depósito
1. **USDC**: se acredita 1:1 en la contabilidad interna.
2. **ETH**: se enruta `ETH → WETH → USDC` vía router Uniswap V2.
3. **Otros ERC20**: deben tener par directo con USDC. Se usa `swapExactTokensForTokens` para convertirlos.

En todos los casos el resultado neto en USDC debe respetar `bankCap`. Si el swap produciría un exceso, la transacción revierte.

### Flujo de retiro
- **USDC**: débito directo y transferencia al usuario.
- **ETH**: el contrato realiza `swapExactTokensForETH` usando el router, con parámetros `minETHOut` y `deadline` provistos por el usuario para controlar slippage.

## 🧱 Contratos

- `src/KipuBankV2.sol`: versión previa, conservada para referencia y compatibilidad.
- `src/KipuBankV3.sol`: implementación nueva con rutas hacia Uniswap V2.
- `src/interfaces/IUniswapV2Router02.sol`: interfaz mínima del router utilizada tanto en producción como en los tests.

## ⚙️ Requisitos y configuración

Este repositorio ahora está preparado para Foundry.

```bash
# Instalar foundry (si no lo tienes)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Instalar dependencias necesarias
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2
forge install smartcontractkit/chainlink-brownie-contracts@1.2.0
```

El archivo `foundry.toml` define:
- `solc_version = 0.8.26`
- Optimizador activado (200 runs)
- Remappings hacia las librerías anteriores

## 🚀 Despliegue (Foundry)

```bash
# Ejemplo Sepolia
forge create src/KipuBankV3.sol:KipuBankV3 \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --constructor-args \
      <admin> \
      <usdc_address> \
      <uniswap_router> \
      <bank_cap_usd6> \
      <withdrawal_limit_usd6>
```

Parámetros clave:
- `admin`: EOA que recibe los roles `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE` y `TREASURER_ROLE`.
- `usdc_address`: token USDC de la red objetivo (6 decimales).
- `uniswap_router`: dirección del router Uniswap V2 compatible.
- `bank_cap_usd6`: capacidad global en unidades de 6 decimales.
- `withdrawal_limit_usd6`: límite por retiro (<= `bankCap`).

## 🕹️ Interacción

| Función | Descripción | Notas |
| --- | --- | --- |
| `depositUSDC(uint256 amount)` | Deposita USDC directo | Requiere `approve` previo |
| `depositETH(uint256 minUSDCOut, uint256 deadline)` | Envía ETH y lo convierte a USDC | `minUSDCOut` controla el slippage, `deadline` debe ser futuro |
| `depositToken(address token, uint256 amount, uint256 minUSDCOut, uint256 deadline)` | Deposita cualquier ERC20 con par directo a USDC | El contrato transfiere el token, aprueba el router y hace el swap |
| `withdrawUSDC(uint256 usd6Amount)` | Retira USDC 1:1 | Respeta `WITHDRAWAL_THRESHOLD_USD6` |
| `withdrawETH(uint256 usd6Amount, uint256 minETHOut, uint256 deadline)` | Swap USDC → ETH y envío | Slippage controlado por el usuario |
| `previewDeposit(address token, uint256 amount)` | Llama a `getAmountsOut` del router | Útil para frontends |
| `previewWithdrawETH(uint256 usd6Amount)` | Calcula ETH estimado vía router | --- |
| `pause()` / `unpause()` | Control de emergencias | Solo `PAUSER_ROLE` |
| `setBankCapUSD6(uint256 newCap)` | Ajusta el límite global | Solo admin |
| `rescue(address token, uint256 amount)` | Recupera fondos extra | Solo `TREASURER_ROLE` |

## 🧪 Tests y cobertura

Los tests viven en `test/` y utilizan mocks livianos para el router, USDC y tokens arbitrarios.

```bash
forge test
forge coverage
```

La suite cubre flujos de depósito para ETH/USDC/ERC20, retiros con swaps, enforcement de `bankCap`, pausas y rutas de error. La meta es superar 50 % de cobertura; verifica el reporte con `forge coverage`.

> ℹ️ Los tests dependen de Foundry. Si ejecutas en un entorno sin `forge`, instala la herramienta o usa GitHub Codespaces/Foundry Docker.

## 🔐 Análisis de amenazas resumido

| Riesgo | Mitigación | Estado |
| --- | --- | --- |
| **Slippage / front-running** | Usuarios fijan `minUSDCOut`/`minETHOut` y `deadline` | Considerar integración con oráculos o permit pools con slippage automático en futuras versiones |
| **Liquidez insuficiente en router** | Tests usan mocks, en producción depende del pool | Supervisar liquidez del par; fallback a Curve/otros routers si se desea robustez |
| **bankCap incumplido** | Se valida con cotización previa y post-swap (revert) | Añadir buffer dinámico y monitoreo externo |
| **Reentradas** | `ReentrancyGuard` + patrón CEI | Mantener auditorías al integrar routers externos |
| **Rug pull de tokens depositados** | Solo se aceptan tokens con par directo a USDC | Agregar listas blancas/negra gestionadas por admin |

Pasos adicionales sugeridos para madurez:
- Monitorizar precios off-chain y suspender depósitos si la desviación contra oráculos supera cierto umbral.
- Integrar múltiples routers (Uniswap/Sushiswap) para mejor ruta y redundancia.
- Añadir límites por usuario y mecanismos de riesgo (p. ej., scoring de tokens).
- Automatizar pruebas de integración en redes de prueba reales.

## 📚 Recursos para auditores y frontends

- Los eventos `KBV3_Deposit` y `KBV3_Withdrawal` emiten token de entrada/salida, montos y USDC acreditado/debitado.
- `getBalanceUSD6(user, address(USDC))` retorna el saldo neto en el banco.
- `previewDeposit` y `previewWithdrawETH` sirven para mostrar estimaciones en UI.
- Roles definidos: `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `TREASURER_ROLE` (valores = `keccak256("…")`).

## 📄 Licencia

MIT.
