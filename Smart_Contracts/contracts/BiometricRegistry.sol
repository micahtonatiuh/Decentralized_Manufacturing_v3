// SPDX-License-Identifier: MIT
//Author: Froylan Cortes
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title BiometricRegistry
 * @dev Manages biometric registration and authentication of operators
 */
contract BiometricRegistry is Ownable, Pausable {
    // Structure for storing operator information
    struct Operator {
        bool isRegistered;            // Register Status
        uint256 lastAuthentication;   // Last authentication timestamp
        uint256 totalOperations;      // Number of operations
        uint256 registrationDate;     // Register Date
        bool isActive;                // State active/inactive
        string role;                  // Operator role
    }

    // Main Mappings
    mapping(address => Operator) public operators;
    mapping(uint256 => address) public operatorByBiometricId;
    mapping(uint256 => bool) public usedBiometricIds;

    // Events
    event OperatorRegistered(address indexed operator, uint256 indexed biometricId, string role);
    event OperatorAuthenticated(address indexed operator, uint256 timestamp);
    event OperatorStatusUpdated(address indexed operator, bool isActive);
    event OperatorRoleUpdated(address indexed operator, string newRole);
    event OperatorRemoved(address indexed operator, uint256 indexed biometricId);

    // Constants
    uint256 public constant AUTH_TIMEOUT = 12 hours;

    /**
     * @dev Constructor
     * @param initialOwner
     */
    constructor(address initialOwner) Ownable(initialOwner){
    }

    // Modifiers
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
     * @dev Register a new trader with their biometric ID
     * @param operator Address of operator
     * @param biometricId unique biometric ID
     * @param role Operator’s
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
     * @dev Authenticate an operator using their biometric ID
     * @param biometricId biometric operator ID
     * @return bool authentication success
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
     * @dev Updates the active/inactive status of an operator
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
     * @dev Update the role of an operator
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
     * @dev Remove an operator from the registry
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
     * @dev Check if an operator is recently authenticated
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
     * @dev Gets the role of an operator
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
     * @dev Gets the statistics of an operator
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
     * @dev unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}