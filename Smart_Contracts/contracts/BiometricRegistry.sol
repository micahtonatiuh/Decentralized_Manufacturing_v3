// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title BiometricRegistry
 * @dev Gestiona el registro y autenticación biométrica de operadores
 */
contract BiometricRegistry is Ownable, Pausable {
    // Estructura para almacenar información del operador
    struct Operator {
        bool isRegistered;            // Estado de registro
        uint256 lastAuthentication;   // Último timestamp de autenticación
        uint256 totalOperations;      // Total de operaciones realizadas
        uint256 registrationDate;     // Fecha de registro
        bool isActive;                // Estado activo/inactivo
        string role;                  // Rol del operador
    }

    // Mappings principales
    mapping(address => Operator) public operators;
    mapping(uint256 => address) public operatorByBiometricId;
    mapping(uint256 => bool) public usedBiometricIds;

    // Eventos
    event OperatorRegistered(address indexed operator, uint256 indexed biometricId, string role);
    event OperatorAuthenticated(address indexed operator, uint256 timestamp);
    event OperatorStatusUpdated(address indexed operator, bool isActive);
    event OperatorRoleUpdated(address indexed operator, string newRole);
    event OperatorRemoved(address indexed operator, uint256 indexed biometricId);

    // Constantes
    uint256 public constant AUTH_TIMEOUT = 12 hours;

    /**
     * @dev Constructor del contrato
     * @param initialOwner La dirección del propietario inicial
     */
    constructor(address initialOwner) Ownable(initialOwner){
    }

    // Modificadores
    modifier operatorExists(address operator) {
        require(operators[operator].isRegistered, "Operator not registered");
        _;
    }

    modifier operatorActive(address operator) {
        require(operators[operator].isActive, "Operator not active");
        _;
    }

    modifier validBiometricId(uint256 biometricId) {
        require(biometricId != 0, "Invalid biometric ID");
        require(!usedBiometricIds[biometricId], "Biometric ID already in use");
        _;
    }

    /**
     * @dev Registra un nuevo operador con su ID biométrico
     * @param operator Dirección del operador
     * @param biometricId ID biométrico único
     * @param role Rol del operador
     */
    function registerOperator(
        address operator,
        uint256 biometricId,
        string memory role
    )
    external
    onlyOwner
    whenNotPaused
    validBiometricId(biometricId)
    {
        require(operator != address(0), "Invalid operator address");
        require(bytes(role).length > 0, "Role cannot be empty");
        require(!operators[operator].isRegistered, "Operator already registered");

        operators[operator] = Operator({
            isRegistered: true,
            lastAuthentication: 0,
            totalOperations: 0,
            registrationDate: block.timestamp,
            isActive: true,
            role: role
        });

        operatorByBiometricId[biometricId] = operator;
        usedBiometricIds[biometricId] = true;

        emit OperatorRegistered(operator, biometricId, role);
    }

    /**
     * @dev Autentica un operador usando su ID biométrico
     * @param biometricId ID biométrico del operador
     * @return bool éxito de la autenticación
     */
    function authenticateOperator(uint256 biometricId)
    external
    whenNotPaused
    returns (bool)
    {
        address operator = operatorByBiometricId[biometricId];
        require(operator != address(0), "Biometric ID not registered");
        require(operators[operator].isActive, "Operator is not active");

        Operator storage op = operators[operator];
        op.lastAuthentication = block.timestamp;
        op.totalOperations++;

        emit OperatorAuthenticated(operator, block.timestamp);
        return true;
    }

    /**
     * @dev Actualiza el estado activo/inactivo de un operador
     */
    function updateOperatorStatus(address operator, bool isActive)
    external
    onlyOwner
    whenNotPaused
    operatorExists(operator)
    {
        operators[operator].isActive = isActive;
        emit OperatorStatusUpdated(operator, isActive);
    }

    /**
     * @dev Actualiza el rol de un operador
     */
    function updateOperatorRole(address operator, string memory newRole)
    external
    onlyOwner
    whenNotPaused
    operatorExists(operator)
    {
        require(bytes(newRole).length > 0, "Role cannot be empty");
        operators[operator].role = newRole;
        emit OperatorRoleUpdated(operator, newRole);
    }

    /**
     * @dev Elimina un operador del registro
     */
    function removeOperator(address operator, uint256 biometricId)
    external
    onlyOwner
    whenNotPaused
    operatorExists(operator)
    {
        delete operators[operator];
        delete operatorByBiometricId[biometricId];
        usedBiometricIds[biometricId] = false;

        emit OperatorRemoved(operator, biometricId);
    }

    /**
     * @dev Verifica si un operador está autenticado recientemente
     */
    function isOperatorAuthenticated(address operator)
    external
    view
    returns (bool)
    {
        if (!operators[operator].isRegistered || !operators[operator].isActive) {
            return false;
        }
        return (block.timestamp - operators[operator].lastAuthentication) <= AUTH_TIMEOUT;
    }

    /**
     * @dev Obtiene el rol de un operador
     */
    function getOperatorRole(address operator)
    external
    view
    operatorExists(operator)
    returns (string memory)
    {
        return operators[operator].role;
    }

    /**
     * @dev Obtiene las estadísticas de un operador
     */
    function getOperatorStats(address operator)
    external
    view
    operatorExists(operator)
    returns (uint256 lastAuth, uint256 totalOps, uint256 regDate, bool isActive)
    {
        Operator storage op = operators[operator];
        return (
            op.lastAuthentication,
            op.totalOperations,
            op.registrationDate,
            op.isActive
        );
    }

    /**
     * @dev Pausa el contrato
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Despausa el contrato
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}