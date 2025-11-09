Markdown

# KipuBankV3 - Bóveda DeFi con Swap Automático

KipuBankV3 es un protocolo de bóveda (vault) de finanzas descentralizadas (DeFi) construido sobre Ethereum. Su función principal es aceptar depósitos en ETH o cualquier token ERC20 (con liquidez en Uniswap V2) y convertirlos automáticamente en **USDC**, que es el único activo de reserva de la bóveda.

Esta V3 simplifica drásticamente la arquitectura de V2, pasando de una contabilidad multi-token compleja (y múltiples oráculos) a una bóveda nativa de USDC. Aprovecha la **composabilidad** de los protocolos DeFi (Uniswap) para manejar la conversión de activos en la entrada.

## 🚀 Contrato Desplegado y Verificado (Entregable)

**Contrato verificado en Sepolia Etherscan:**
[https://sepolia.etherscan.io/address/0xe4de0d7995d0e307da31f3f020b8c2c7d255db6a#code](https://sepolia.etherscan.io/address/0xe4de0d7995d0e307da31f3f020b8c2c7d255db6a#code)

## 🏛️ Arquitectura y Flujo

1.  **Depósito de USDC:** El USDC se transfiere 1:1 al saldo del usuario.
2.  **Depósito de ETH:** El contrato envuelve el ETH a WETH, aprueba el WETH al Router de Uniswap V2 y ejecuta un swap `WETH -> USDC`.
3.  **Depósito de ERC20 (ej. LINK):** El contrato aprueba el token al Router y ejecuta un swap `TOKEN -> USDC`.
4.  **Contabilidad:** El monto de USDC resultante del swap (o del depósito directo) se suma al `bankCap` total y al saldo (`balances`) del usuario.
5.  **Retiro:** Los usuarios solo pueden retirar USDC.

---

## 🛠️ Entorno y Pruebas (Foundry)

Este proyecto está construido 100% con Foundry.

### Setup (Instalación)

```bash
# 1. Clonar el repositorio

git clone https://github.com/Martin-Mancilla-98/kipubank-v3
cd kipubank-v3

# 2. Instalar dependencias (OpenZeppelin, Uniswap)
forge install
Pruebas (Métodos de Prueba)
Para ejecutar la suite de pruebas (que cumple con >80% de cobertura), se requiere un archivo .env en la raíz del proyecto.

1. Crear el archivo .env Crea un archivo llamado .env y añade tus claves :

Bash

# .env
SEPOLIA_RPC_URL="TU_URL_DE_ALCHEMY_SEPOLIA"
PRIVATE_KEY="TU_LLAVE_PRIVADA_NUEVA"
ETHERSCAN_API_KEY="TU_API_KEY_DE_ETHERSCAN"
2. Ejecutar las Pruebas Una vez que tu .env esté listo, ejecuta los siguientes comandos:

Bash

# 1. Cargar variables de entorno
source .env 

# 2. Ejecutar pruebas
forge test
Resultado de las Pruebas:

Suite result: ok. 8 passed; 0 failed; 0 skipped
Cobertura de Pruebas (Requisito >50%)
El proyecto cumple y supera el requisito de cobertura del 50%, alcanzando un 89.74% en el contrato principal KipuBankV3.sol (según la última ejecución de forge coverage).

Bash

# Ejecutar reporte de cobertura
forge coverage
╭────────────────────┬─────────┬──────────────┬────────────┬─────────╮
│ File               │ % Lines │ % Statements │ % Branches │ % Funcs │
╞════════════════════╪═════════╪══════════════╪════════════╪═════════╡
│ src/KipuBankV3.sol │ 89.74%  │ 90.36%       │ 45.45%     │ 80.00%  │
│ Total              │ 89.74%  │ 90.36%       │ 45.45%     │ 80.00%  │
╰────────────────────┴─────────┴──────────────┴────────────┴─────────╯
🔬 Informe de Análisis de Amenazas y Decisiones de Diseño
(Requisito de la consigna para auditoría y madurez del protocolo).

1. Riesgo de Reentrada (Ataque)
Amenaza: Un token ERC20 malicioso (como ERC777) podría usar un hook en transferFrom para volver a llamar a una función de depósito o retiro antes de que el estado se actualice.

Mitigación: El contrato hereda de ReentrancyGuard de OpenZeppelin. Todas las funciones que mueven fondos (depositarToken, depositarETH, retirar) están protegidas con el modificador nonReentrant.

2. Slippage / Front-Running en Swaps (Ataque)
Amenaza: Al realizar un swap, un atacante (bot de MEV) puede "ver" nuestra transacción en el mempool, comprar el token antes que nosotros (subiendo el precio) y vendérnoslo más caro, resultando en menos USDC para el usuario.

Mitigación: Las funciones depositarToken y depositarETH requieren un parámetro _minAmountOut. El Router de Uniswap V2 revertirá la transacción si no puede garantizar esa cantidad mínima de USDC.

Decisión de Diseño (Trade-off): La función receive() nativa de Solidity ha sido deshabilitada (revierte con UsarFuncionDepositarETH). Esta es una decisión de seguridad consciente, ya que receive() no puede aceptar un parámetro _minAmountOut, exponiendo a los usuarios a un ataque de slippage total.

3. Aprobaciones de Tokens (Seguridad)
Amenaza: Aprobaciones infinitas (type(uint256).max) al Router de Uniswap pueden ser un riesgo si el Router es comprometido.

Mitigación: El contrato utiliza el patrón "approve-on-spend" (Aprobar al gastar). Solo se aprueba al Router el _monto exacto del depósito, justo antes de ejecutar el swap. Se usa el patrón moderno safeDecreaseAllowance / safeIncreaseAllowance (para OpenZeppelin v5) para evitar errores de aprobación con ciertos tokens.

4. Riesgo del Protocolo Externo (Confianza)
Amenaza: El contrato depende funcionalmente de Uniswap V2. Si el Router de Uniswap es hackeado, tiene un bug, o es pausado, los depósitos de tokens (no-USDC) fallarán.

Mitigación: Esta es una confianza inherente. Se eligió Uniswap V2 por ser uno de los protocolos más antiguos y auditados ("battle-tested") del ecosistema.

5. Riesgo de Centralización (Admin Role)
Amenaza: Una cuenta con ADMIN_ROLE (inicialmente el desplegador) tiene el poder de cambiar el bankCap y el limiteRetiroPorTx. Si esta llave es comprometida, puede afectar la operación del banco (ej. setBankCap(0) para bloquear depósitos).

Mitigación (Madurez Futura): Para una versión de producción, el ADMIN_ROLE debería ser transferido a un contrato Timelock o a un Safe (Gnosis) multi-firma, para que ningún individuo tenga control unilateral y las acciones requieran un período de espera.

6. Cumplimiento de Feedback Anterior (Aprendizaje)
Contadores (Feedback TP3): Se incluyeron las variables totalDepositos y totalRetiros, que el profesor marcó como faltantes en V2.

Errores (Feedback TP3): Se eliminaron todos los require strings y se reemplazaron por Errores Personalizados, ahorrando gas y mejorando la legibilidad.

Seguridad ERC20 (Feedback TP3): Se utiliza SafeERC20 de OpenZeppelin para todas las interacciones de tokens.