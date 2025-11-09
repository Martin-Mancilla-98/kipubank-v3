// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// --- Importaciones de OpenZeppelin (Requisito TP3 Feedback) ---
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// --- Importaciones de Interfaces (Requisito TP4) ---
// LÍNEA CORREGIDA
import "v2-periphery/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IWETH.sol"; // Importamos nuestra interfaz local

/**
 * @title KipuBankV3
 * @author Martín (Desarrollado con asistencia de IA)
 * @notice Bóveda DeFi que convierte automáticamente todos los depósitos (ETH y ERC20)
 * en USDC usando Uniswap V2.
 * @dev Hereda de AccessControl para roles y ReentrancyGuard para seguridad (Feedback TP3).
 * Utiliza SafeERC20 para todas las interacciones con tokens.
 */
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    // ============================
    // Errores Personalizados
    // (Feedback TP3: No usar 'require' strings)
    // ============================
    error MontoCero();
    error DireccionInvalida();
    error SaldoInsuficiente();
    error BankCapExcedido(uint256 actual, uint256 solicitado, uint256 limite);
    error LimiteRetiroExcedido(uint256 solicitado, uint256 limite);
    error UsarFuncionDepositarETH();
    error TransferenciaFallida();
    error SlippageExcedido();

    // ============================
    // Roles y Constantes
    // ============================
    /// @notice Rol para funciones administrativas (ej. cambiar bankCap).
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // --- Interfaces Externas (Requisito TP4) ---
    /// @notice Router de Uniswap V2 para ejecutar swaps.
    IUniswapV2Router02 public immutable i_router;
    /// @notice Interfaz del token WETH (Wrapped ETH).
    IWETH public immutable i_weth;
    /// @notice Interfaz del token USDC (nuestro token de bóveda).
    IERC20 public immutable i_usdc;

    // ============================
    // Variables de Estado
    // ============================

    /// @notice Límite máximo de USDC que el banco puede almacenar.
    uint256 public bankCap;
    /// @notice Límite máximo de USDC por transacción de retiro.
    uint256 public limiteRetiroPorTx;
    /// @notice Total de USDC que el contrato posee actualmente.
    uint256 public totalUSDCEnBanco;

    /// @notice Contabilidad principal: usuario => saldo en USDC.
    /// @dev (Requisito TP4: contabilidad simplificada solo en USDC)
    mapping(address => uint256) public balances;

    // --- Contadores (Requisito TP3 Feedback) ---
    /// @notice Contador total de depósitos exitosos.
    uint256 public totalDepositos;
    /// @notice Contador total de retiros exitosos.
    uint256 public totalRetiros;

    // ============================
    // Eventos
    // ============================
    event Deposito(
        address indexed usuario,
        address indexed tokenIn,
        uint256 montoIn,
        uint256 usdcRecibido
    );
    event Retiro(address indexed usuario, uint256 montoUSDC);
    event BankCapActualizado(uint256 nuevoCap);
    event LimiteRetiroActualizado(uint256 nuevoLimite);

    // ============================
    // Constructor
    // ============================
    constructor(
        address _router,
        address _weth,
        address _usdc,
        uint256 _bankCapInicial, // en USDC, con 6 decimales
        uint256 _limiteRetiroInicial // en USDC, con 6 decimales
    ) {
        if (
            _router == address(0) ||
            _weth == address(0) ||
            _usdc == address(0)
        ) {
            revert DireccionInvalida();
        }

        i_router = IUniswapV2Router02(_router);
        i_weth = IWETH(_weth);
        i_usdc = IERC20(_usdc);

        bankCap = _bankCapInicial;
        limiteRetiroPorTx = _limiteRetiroInicial;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // ============================
    // Funciones Administrativas
    // (Requisito V2 Preservado)
    // ============================

    /**
     * @notice Actualiza el límite máximo (bank cap) de la bóveda.
     * @param _nuevoCap El nuevo límite, en unidades de USDC (6 decimales).
     */
    function setBankCap(uint256 _nuevoCap) external onlyRole(ADMIN_ROLE) {
        bankCap = _nuevoCap;
        emit BankCapActualizado(_nuevoCap);
    }

    /**
     * @notice Actualiza el límite máximo por transacción de retiro.
     * @param _nuevoLimite El nuevo límite, en unidades de USDC (6 decimales).
     */
    function setLimiteRetiroPorTx(
        uint256 _nuevoLimite
    ) external onlyRole(ADMIN_ROLE) {
        limiteRetiroPorTx = _nuevoLimite;
        emit LimiteRetiroActualizado(_nuevoLimite);
    }

    // ============================
    // Funciones de Depósito (Núcleo TP4)
    // ============================

    /**
     * @notice Deposita tokens ERC20.
     * @dev Si el token es USDC, se acredita directamente.
     * Si es otro token, lo intercambia (swappea) por USDC vía Uniswap V2.
     * @param _token La dirección del token a depositar.
     * @param _monto La cantidad de tokens a depositar (en decimales del token).
     * @param _minAmountOut La cantidad mínima de USDC esperada (protección slippage).
     */
    function depositarToken(
        address _token,
        uint256 _monto,
        uint256 _minAmountOut
    ) external nonReentrant { // (Feedback TP3: Usar ReentrancyGuard)
        if (_monto == 0) revert MontoCero();

        // --- 1. Interacción (Pull) ---
        // (Patrón seguro: Recibir el token ANTES de cualquier efecto)
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _monto);

        uint256 usdcRecibido;

        if (_token == address(i_usdc)) {
            // --- Caso 1: Depósito directo de USDC ---
            usdcRecibido = _monto;
        } else {
            // --- Caso 2: Swap de Token -> USDC ---
            // (Feedback TP3: Aprobación por monto exacto)
  // LÍNEAS CORREGIDAS (Patrón moderno y seguro para aprobar)
// Primero, reseteamos cualquier aprobación anterior a 0
uint256 currentAllowance = IERC20(_token).allowance(address(this), address(i_router));
if (currentAllowance > 0) {
    IERC20(_token).safeDecreaseAllowance(address(i_router), currentAllowance);
}
// Luego, damos la aprobación exacta para este swap
IERC20(_token).safeIncreaseAllowance(address(i_router), _monto);

            address[] memory path = new address[](2);
            path[0] = _token;
            path[1] = address(i_usdc);

            uint256 usdcAntes = i_usdc.balanceOf(address(this));

            // (Interacción 2: El Swap)
            i_router.swapExactTokensForTokens(
                _monto,
                _minAmountOut,
                path,
                address(this), // Enviar USDC a este contrato
                block.timestamp // Deadline simple
            );

            uint256 usdcDespues = i_usdc.balanceOf(address(this));
            usdcRecibido = usdcDespues - usdcAntes;

            // (El router de Uniswap V2 ya revierte si usdcRecibido < _minAmountOut)
        }

        // --- 2. Contabilidad (Checks y Effects) ---
        _acreditarDeposito(msg.sender, _token, _monto, usdcRecibido);
    }

    /**
     * @notice Deposita ETH (token nativo).
     * @dev Envuelve el ETH en WETH y lo intercambia por USDC vía Uniswap V2.
     * @param _minAmountOut La cantidad mínima de USDC esperada (protección slippage).
     */
    function depositarETH(
        uint256 _minAmountOut
    ) external payable nonReentrant {
        uint256 monto = msg.value;
        if (monto == 0) revert MontoCero();

        // --- 1. Swap (WETH -> USDC) ---
        i_weth.deposit{value: monto}();
        // LÍNEAS CORREGIDAS (Mismo patrón, pero para WETH)
uint256 currentWethAllowance = i_weth.allowance(address(this), address(i_router));
if (currentWethAllowance > 0) {
    i_weth.safeDecreaseAllowance(address(i_router), currentWethAllowance);
}
i_weth.safeIncreaseAllowance(address(i_router), monto);

        address[] memory path = new address[](2);
        path[0] = address(i_weth);
        path[1] = address(i_usdc);

        uint256 usdcAntes = i_usdc.balanceOf(address(this));

        i_router.swapExactTokensForTokens(
            monto,
            _minAmountOut,
            path,
            address(this),
            block.timestamp
        );

        uint256 usdcDespues = i_usdc.balanceOf(address(this));
        uint256 usdcRecibido = usdcDespues - usdcAntes;

        // --- 2. Contabilidad (Checks y Effects) ---
        _acreditarDeposito(
            msg.sender,
            address(i_weth), // Registramos WETH como el "token" de entrada
            monto,
            usdcRecibido
        );
    }

    /**
     * @notice Lógica interna para chequear el Bank Cap y acreditar el depósito.
     * @dev (Requisito TP4: Respetar Bank Cap)
     */
    function _acreditarDeposito(
        address _usuario,
        address _tokenIn,
        uint256 _montoIn,
        uint256 _usdcRecibido
    ) internal {
        // --- CHECKS ---
        uint256 nuevoTotalBanco = totalUSDCEnBanco + _usdcRecibido;
        if (nuevoTotalBanco > bankCap) {
            revert BankCapExcedido(totalUSDCEnBanco, _usdcRecibido, bankCap);
        }

        // --- EFFECTS ---
        totalUSDCEnBanco = nuevoTotalBanco;
        balances[_usuario] += _usdcRecibido;
        totalDepositos++; // (Feedback TP3: Incluir contador)

        emit Deposito(_usuario, _tokenIn, _montoIn, _usdcRecibido);
    }

    // ============================
    // Función de Retiro
    // (Requisito V2 Preservado, simplificado a USDC)
    // ============================

    /**
     * @notice Retira USDC de la bóveda.
     * @param _montoUSDC La cantidad de USDC a retirar.
     */
    function retirar(uint256 _montoUSDC) external nonReentrant {
        // --- CHECKS (Patrón C-E-I) ---
        if (_montoUSDC == 0) revert MontoCero();
        uint256 saldoUsuario = balances[msg.sender];
        if (_montoUSDC > saldoUsuario) revert SaldoInsuficiente();
        if (_montoUSDC > limiteRetiroPorTx) {
            revert LimiteRetiroExcedido(_montoUSDC, limiteRetiroPorTx);
        }

        // --- EFFECTS ---
        balances[msg.sender] = saldoUsuario - _montoUSDC;
        totalUSDCEnBanco -= _montoUSDC;
        totalRetiros++; // (Feedback TP3: Incluir contador)

        // --- INTERACTION ---
        // (Feedback TP3: Usar SafeERC20)
        i_usdc.safeTransfer(msg.sender, _montoUSDC);

        emit Retiro(msg.sender, _montoUSDC);
    }

    // ============================
    // Función de Recepción (Seguridad)
    // ============================

    /**
     * @notice Bloquea la recepción directa de ETH.
     * @dev (Decisión de diseño: Previene slippage/front-running al
     * no poder proveer un `_minAmountOut`.)
     */
    receive() external payable {
        revert UsarFuncionDepositarETH();
    }

    // ============================
    // Funciones de Vista
    // ============================

    /**
     * @notice Devuelve el saldo en USDC de un usuario.
     */
    function getUsdcBalance(
        address _usuario
    ) external view returns (uint256) {
        return balances[_usuario];
    }

    /**
     * @notice Devuelve estadísticas clave del banco.
     */
    function getBankStats() external view returns (
        uint256 cap,
        uint256 totalEnBoveda,
        uint256 depositos,
        uint256 retiros
    ) {
        return (bankCap, totalUSDCEnBanco, totalDepositos, totalRetiros);
    }
}