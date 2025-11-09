// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IWETH
 * @notice Interfaz simple para el contrato WETH9.
 * Incluye `deposit` (payable), `withdraw`, y funciones ERC20.
 */
interface IWETH is IERC20 {
    /**
     * @notice Deposita ETH para recibir WETH (envuelve ETH).
     */
    function deposit() external payable;

    /**
     * @notice Retira WETH para recibir ETH (desenvuelve WETH).
     * @param wad La cantidad de WETH a retirar.
     */
    function withdraw(uint256 wad) external;
}