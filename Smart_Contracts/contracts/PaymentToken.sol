// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
* @title PaymentToken
* @dev Token ERC20 para pagos y bonificaciones en el sistema de manufactura
*/
contract PaymentToken is ERC20, ERC20Burnable, Pausable, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Eventos específicos
    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event EmergencyTransfer(address indexed from, address indexed to, uint256 amount);

    // Errors
    error InvalidParameters();
    error InsufficientBalance();
    error NotAuthorized();

    /**
     * @dev Constructor que configura el nombre, símbolo y roles iniciales
   */
    constructor() ERC20("Manufacturing Payment Token", "MPT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @dev Pausa todas las transferencias de tokens
   * Solo puede ser llamado por una cuenta con rol PAUSER_ROLE
   */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Despausa todas las transferencias de tokens
   * Solo puede ser llamado por una cuenta con rol PAUSER_ROLE
   */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Crea nuevos tokens
   * @param to dirección que recibirá los tokens
   * @param amount cantidad de tokens a crear
   */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        if(to == address(0) || amount == 0) revert InvalidParameters();
        _mint(to, amount);
    }

    /**
     * @dev Añade una nueva dirección como minter
   * @param account dirección a añadir como minter
   */
    function addMinter(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(account == address(0)) revert InvalidParameters();
        grantRole(MINTER_ROLE, account);
        emit MinterAdded(account);
    }

    /**
     * @dev Remueve una dirección como minter
   * @param account dirección a remover como minter
   */
    function removeMinter(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(account == address(0)) revert InvalidParameters();
        revokeRole(MINTER_ROLE, account);
        emit MinterRemoved(account);
    }

    /**
     * @dev Transfiere tokens en caso de emergencia
   * @param from dirección desde donde transferir
   * @param to dirección que recibirá los tokens
   * @param amount cantidad de tokens a transferir
   */
    function emergencyTransfer(
        address from,
        address to,
        uint256 amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(to == address(0) || amount == 0) revert InvalidParameters();
        if(balanceOf(from) < amount) revert InsufficientBalance();

        _transfer(from, to, amount);
        emit EmergencyTransfer(from, to, amount);
    }

    /**
     * @dev Quema tokens de una dirección específica
   * @param from dirección de la cual quemar tokens
   * @param amount cantidad de tokens a quemar
   */
    function burnFrom(address from, uint256 amount)
    public
    override
    onlyRole(MINTER_ROLE)
    {
        if(from == address(0) || amount == 0) revert InvalidParameters();
        if(balanceOf(from) < amount) revert InsufficientBalance();

        _burn(from, amount);
    }

    /**
     * @dev Hook que se ejecuta antes de cualquier transferencia de tokens
   */
    function _beforeTokenTransfer(
        address,
        address,
        uint256
    ) internal virtual {
        require(!paused(), "ERC20Pausable: token transfer while paused");
    }

    /**
     * @dev Soporta interfaces de AccessControl y ERC20
   */
    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(AccessControl)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Función para recibir ETH (necesaria para recibir ETH)
   */
    receive() external payable {
        revert("Direct ETH payments not accepted");
    }
}