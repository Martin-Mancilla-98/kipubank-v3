// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// --- Importaciones de Foundry ---
import "forge-std/Test.sol"; // La librería de pruebas de Foundry
import "forge-std/console.sol"; // Para logging

// --- Importaciones de nuestro Contrato e Interfaces ---
import "../src/KipuBankV3.sol";
import "../src/interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract KipuBankV3Test is Test {
    // ============================
    // Variables del Entorno de Prueba
    // ============================

    // --- Direcciones en Sepolia ---
    // Router Uniswap V2 en Sepolia
    address constant ROUTER_ADDR = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    // WETH en Sepolia
    address constant WETH_ADDR = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    // USDC en Sepolia (Mock)
    address constant USDC_ADDR = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    // LINK en Sepolia
    address constant LINK_ADDR = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
// --- Instancias de Contratos ---
KipuBankV3 public bank;
IWETH public weth = IWETH(WETH_ADDR);
IERC20 public usdc = IERC20(USDC_ADDR);
IERC20 public link = IERC20(LINK_ADDR);
    // --- Usuarios de Prueba ---
    address public user = makeAddr("user"); // Un usuario de prueba
    address public admin; // El admin (dueño) del contrato

    // --- Valores Constantes para Pruebas ---
    uint256 constant BANK_CAP_INICIAL = 1_000_000 * 1e6; // 1M USDC
    uint256 constant LIMITE_RETIRO_INICIAL = 10_000 * 1e6; // 10k USDC
    uint256 constant USDC_DEPOSIT_AMOUNT = 5_000 * 1e6; // 5k USDC
    uint256 constant LINK_DEPOSIT_AMOUNT = 100 * 1e18; // 100 LINK
    uint256 constant ETH_DEPOSIT_AMOUNT = 1 ether; // 1 ETH

    // ============================
    // setUp: Configuración de la Prueba
    // ============================

    /// @notice Esta función se ejecuta ANTES de cada prueba (test)
    function setUp() public {
        // 1. Forkear la testnet de Sepolia
        try vm.envString("SEPOLIA_RPC_URL") returns (string memory sepoliaRpcUrl) {
            require(bytes(sepoliaRpcUrl).length > 0, "SEPOLIA_RPC_URL esta vacia");
            console.log("Usando RPC URL:", sepoliaRpcUrl);
            
            try vm.createSelectFork(sepoliaRpcUrl) returns (uint256 forkId) {
                console.log("Fork creado con ID:", forkId);
                
                // 2. Definir admin
                admin = address(this);
                console.log("Admin configurado:", admin);
                
                try new KipuBankV3(
                    ROUTER_ADDR,
                    WETH_ADDR,
                    USDC_ADDR,
                    BANK_CAP_INICIAL,
                    LIMITE_RETIRO_INICIAL
                ) returns (KipuBankV3 newBank) {
                    bank = newBank;
                    console.log("Contrato desplegado en:", address(bank));
                    
                    // 4. Preparar fondos de prueba
                    console.log("Verificando direcciones de tokens...");
                    require(USDC_ADDR != address(0), "USDC_ADDR es zero address");
                    require(LINK_ADDR != address(0), "LINK_ADDR es zero address");
                    
                    console.log("USDC address:", USDC_ADDR);
                    console.log("LINK address:", LINK_ADDR);
                    
                    console.log("Asignando fondos de prueba...");
                    
                    // Asignar ETH
                    vm.deal(user, ETH_DEPOSIT_AMOUNT);
                    console.log("ETH asignado correctamente");
                    
                    // Asignar tokens usando deal para ERC20
                    deal(USDC_ADDR, user, USDC_DEPOSIT_AMOUNT, true);  // true = ajustar el total supply
                    deal(LINK_ADDR, user, LINK_DEPOSIT_AMOUNT, true);
                    
                    // Verificar balances
                    console.log("Tokens asignados. Balances actuales:");
                    console.log("USDC:", IERC20(USDC_ADDR).balanceOf(user) / 1e6, "USDC");
                    console.log("LINK:", IERC20(LINK_ADDR).balanceOf(user) / 1e18, "LINK");
                    
                } catch Error(string memory reason) {
                    console.log("Error al desplegar contrato:", reason);
                    revert(string(abi.encodePacked("Error al desplegar contrato: ", reason)));
                }
            } catch Error(string memory reason) {
                console.log("Error al crear fork:", reason);
                revert("Error al crear fork");
            }
        } catch Error(string memory reason) {
            console.log("Error al obtener SEPOLIA_RPC_URL:", reason);
            revert("Error al obtener SEPOLIA_RPC_URL");
        }

        // 2. Definir quién es el admin (será 'this', la dirección de este contrato de prueba)
        admin = address(this);

        // 3. Desplegar el banco (simulando ser el admin)
        vm.prank(admin);
        bank = new KipuBankV3(
            ROUTER_ADDR,
            WETH_ADDR,
            USDC_ADDR,
            BANK_CAP_INICIAL,
            LIMITE_RETIRO_INICIAL
        );

        // 4. "Repartir" fondos a nuestro usuario de prueba
        // Cheatcode `deal`: Da tokens/ETH a una dirección
        deal(USDC_ADDR, user, USDC_DEPOSIT_AMOUNT); // Dar 5k USDC al 'user'
        deal(LINK_ADDR, user, LINK_DEPOSIT_AMOUNT); // Dar 100 LINK al 'user'
        deal(user, ETH_DEPOSIT_AMOUNT); // Dar 1 ETH al 'user'
    }

    // ============================
    // Pruebas "Happy Path" (Lo que debe funcionar)
    // ============================

    /// @notice Prueba el depósito directo de USDC
    function test_DepositarUSDC() public {
        // 1. Simular que el 'user' aprueba el gasto de USDC
        vm.prank(user);
        usdc.approve(address(bank), USDC_DEPOSIT_AMOUNT);

        // 2. Simular que el 'user' llama a 'depositarToken'
        vm.prank(user);
        bank.depositarToken(USDC_ADDR, USDC_DEPOSIT_AMOUNT, USDC_DEPOSIT_AMOUNT);

        // 3. Verificar los resultados
        assertEq(bank.balances(user), USDC_DEPOSIT_AMOUNT, "El saldo del usuario no se actualizo");
        assertEq(bank.totalUSDCEnBanco(), USDC_DEPOSIT_AMOUNT, "El total del banco no se actualizo");
        assertEq(bank.totalDepositos(), 1, "El contador de depositos fallo");
    }

    /// @notice Prueba el depósito de un token (LINK) que requiere un swap
    function test_DepositarTokenConSwap() public {
        // 1. Simular que el 'user' aprueba LINK
        vm.prank(user);
        link.approve(address(bank), LINK_DEPOSIT_AMOUNT);

        // 2. Simular que el 'user' llama a 'depositarToken' (con slippage 0)
        uint256 minAmountOut = 0; // Para la prueba, 0 está bien.
        vm.prank(user);
        bank.depositarToken(LINK_ADDR, LINK_DEPOSIT_AMOUNT, minAmountOut);

        // 3. Verificar que se recibió USDC (no sabemos cuánto, solo que sea > 0)
        assertTrue(bank.balances(user) > 0, "No se recibio USDC del swap de LINK");
        assertTrue(bank.totalUSDCEnBanco() > 0, "El total del banco no se actualizo tras el swap");
        assertEq(bank.totalDepositos(), 1, "El contador de depositos fallo");
    }

    /// @notice Prueba el depósito de ETH que requiere un swap
    function test_DepositarETHConSwap() public {
        uint256 minAmountOut = 0; // Para la prueba, 0 está bien.

        // 1. Simular que el 'user' llama a 'depositarETH' enviando 1 ETH
        vm.prank(user);
        bank.depositarETH{value: ETH_DEPOSIT_AMOUNT}(minAmountOut);

        // 2. Verificar que se recibió USDC
        assertTrue(bank.balances(user) > 0, "No se recibio USDC del swap de ETH");
        assertTrue(bank.totalUSDCEnBanco() > 0, "El total del banco no se actualizo tras el swap");
        assertEq(bank.totalDepositos(), 1, "El contador de depositos fallo");
    }

    /// @notice Prueba un retiro exitoso de USDC
    function test_RetirarUSDC() public {
        // 1. Necesitamos depositar primero
        test_DepositarUSDC();

        uint256 montoRetiro = 1_000 * 1e6; // 1k USDC
        uint256 balanceUSDCUsuario_Antes = usdc.balanceOf(user);

        // 2. Simular que el 'user' llama a 'retirar'
        vm.prank(user);
        bank.retirar(montoRetiro);

        // 3. Verificar
        assertEq(bank.balances(user), USDC_DEPOSIT_AMOUNT - montoRetiro, "El saldo interno no se redujo");
        assertEq(usdc.balanceOf(user), balanceUSDCUsuario_Antes + montoRetiro, "El usuario no recibio su USDC");
        assertEq(bank.totalRetiros(), 1, "El contador de retiros fallo");
    }

    // ============================
    // Pruebas "Sad Path" (Lo que debe fallar)
    // (Usamos `vm.expectRevert`)
    // ============================

    /// @notice Prueba que el depósito falle si supera el bank cap
    function test_Falla_DepositoSobreBankCap() public {
        // 1. Bajar el bank cap a 1,000 USDC
        uint256 nuevoCap = 1_000 * 1e6;
        vm.prank(admin);
        bank.setBankCap(nuevoCap);

        // 2. Aprobar el depósito de 5,000 USDC
        vm.prank(user);
        usdc.approve(address(bank), USDC_DEPOSIT_AMOUNT);

        // 3. Esperar que la siguiente llamada REVIERTA con nuestro error
        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.BankCapExcedido.selector,
                0, // total actual en banco
                USDC_DEPOSIT_AMOUNT, // monto solicitado
                nuevoCap // el límite
            )
        );

        // 4. Ejecutar la llamada que debe fallar
        vm.prank(user);
        bank.depositarToken(USDC_ADDR, USDC_DEPOSIT_AMOUNT, USDC_DEPOSIT_AMOUNT);
    }

    /// @notice Prueba que falle el retiro si no hay saldo
    function test_Falla_RetiroSaldoInsuficiente() public {
        // 1. Esperar que revierta con el error SaldoInsuficiente
        vm.expectRevert(KipuBankV3.SaldoInsuficiente.selector);

        // 2. Intentar retirar 1 USDC sin tener saldo
        vm.prank(user);
        bank.retirar(1 * 1e6);
    }

    /// @notice Prueba que falle el retiro si supera el límite por TX
    function test_Falla_RetiroLimiteTx() public {
        // 1. Depositar 5k USDC
        test_DepositarUSDC();

        // 2. Bajar el límite de retiro a 1k USDC
        uint256 nuevoLimite = 1_000 * 1e6;
        vm.prank(admin);
        bank.setLimiteRetiroPorTx(nuevoLimite);

        // 3. Intentar retirar 2k USDC (más que el límite)
        uint256 montoRetiro = 2_000 * 1e6;

        // 4. Esperar que revierta con nuestro error
        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.LimiteRetiroExcedido.selector,
                montoRetiro,
                nuevoLimite
            )
        );

        // 5. Ejecutar la llamada que debe fallar
        vm.prank(user);
        bank.retirar(montoRetiro);
    }

    /// @notice Prueba que falle si se envía ETH directo (nuestra decisión de seguridad)
    function test_Falla_Receive() public {
        vm.expectRevert(KipuBankV3.UsarFuncionDepositarETH.selector);
        
        vm.deal(user, 1 ether);  // Asegurar que el usuario tiene ETH para enviar
        vm.prank(user);
        (bool success, ) = address(bank).call{value: 1 ether}("");
        
        // No necesitamos verificar success porque vm.expectRevert ya lo hace
    }
}