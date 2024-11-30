// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IIPFSRegistry {
    function isDesignLicensed(string memory designHash, address user) external view returns (bool);
}

interface IPrinterRegistry {
    function isPrinterOperational(string memory printerId, uint256 requiredTemp) external view returns (bool);
}

interface IBiometricRegistry {
    function isOperatorAuthenticated(address operator) external view returns (bool);
}

/**
 * @title ManufacturingProcess
 * @dev Gestiona el proceso completo de manufactura
 */
contract ManufacturingProcess is Ownable, Pausable {
    // Estructura principal del proceso de manufactura
    struct ManufacturingRecord {
        string designHash;            // Hash IPFS del diseño
        address operator;             // Operador asignado
        string printerId;             // ID de la impresora
        uint256 requiredTemp;         // Temperatura requerida
        bool printerVerified;         // Verificación de impresora
        bool visionVerified;          // Verificación de visión
        bool robotPickupComplete;     // Recolección por robot
        bool assemblyComplete;        // Ensamblaje completado
        uint256 startTime;           // Tiempo de inicio
        uint256 completionTime;      // Tiempo de finalización
        string status;               // Estado actual
    }

    // Mappings y variables de estado
    mapping(uint256 => ManufacturingRecord) public records;
    uint256 public currentRecordId;

    // Interfaces de contratos externos
    IIPFSRegistry public ipfsRegistry;
    IPrinterRegistry public printerRegistry;
    IBiometricRegistry public biometricRegistry;

    // Eventos
    event ManufacturingStarted(uint256 indexed recordId, string designHash, address operator);
    event PrinterVerified(uint256 indexed recordId, string printerId);
    event VisionCheckComplete(uint256 indexed recordId, bool passed);
    event RobotPickupComplete(uint256 indexed recordId);
    event AssemblyComplete(uint256 indexed recordId);
    event ManufacturingComplete(uint256 indexed recordId, uint256 completionTime);
    event StatusUpdated(uint256 indexed recordId, string newStatus);

    /**
     * @dev Constructor del contrato
     */
    constructor(
        address initialOwner,
        address _ipfsRegistry,
        address _printerRegistry,
        address _biometricRegistry
    ) Ownable(initialOwner) Pausable() {
        ipfsRegistry = IIPFSRegistry(_ipfsRegistry);
        printerRegistry = IPrinterRegistry(_printerRegistry);
        biometricRegistry = IBiometricRegistry(_biometricRegistry);
    }

    // Modificadores
    modifier recordExists(uint256 recordId) {
        require(records[recordId].startTime != 0, "Record does not exist");
        _;
    }

    modifier onlyAuthenticatedOperator() {
        require(biometricRegistry.isOperatorAuthenticated(msg.sender), "Operator not authenticated");
        _;
    }

    /**
     * @dev Inicia un nuevo proceso de manufactura
     */
    function startManufacturing(
        string memory designHash,
        string memory printerId,
        uint256 requiredTemp
    )
    external
    whenNotPaused
    onlyAuthenticatedOperator
    returns (uint256)
    {
        require(bytes(designHash).length > 0, "Invalid design hash");
        require(bytes(printerId).length > 0, "Invalid printer ID");
        require(requiredTemp > 0, "Invalid temperature");
        require(
            ipfsRegistry.isDesignLicensed(designHash, msg.sender),
            "Design not licensed"
        );

        currentRecordId++;

        records[currentRecordId] = ManufacturingRecord({
            designHash: designHash,
            operator: msg.sender,
            printerId: printerId,
            requiredTemp: requiredTemp,
            printerVerified: false,
            visionVerified: false,
            robotPickupComplete: false,
            assemblyComplete: false,
            startTime: block.timestamp,
            completionTime: 0,
            status: "STARTED"
        });

        emit ManufacturingStarted(currentRecordId, designHash, msg.sender);
        return currentRecordId;
    }

    /**
     * @dev Verifica la impresora asignada
     */
    function verifyPrinter(uint256 recordId)
    external
    whenNotPaused
    recordExists(recordId)
    onlyAuthenticatedOperator
    {
        ManufacturingRecord storage record = records[recordId];
        require(!record.printerVerified, "Printer already verified");
        require(
            printerRegistry.isPrinterOperational(record.printerId, record.requiredTemp),
            "Printer not operational"
        );

        record.printerVerified = true;
        record.status = "PRINTER_VERIFIED";

        emit PrinterVerified(recordId, record.printerId);
        emit StatusUpdated(recordId, record.status);
    }

    /**
     * @dev Registra la verificación de visión
     */
    function setVisionVerification(uint256 recordId, bool passed)
    external
    whenNotPaused
    recordExists(recordId)
    onlyAuthenticatedOperator
    {
        ManufacturingRecord storage record = records[recordId];
        require(record.printerVerified, "Printer not verified");
        require(!record.visionVerified, "Vision already verified");

        record.visionVerified = passed;
        record.status = passed ? "VISION_PASSED" : "VISION_FAILED";

        emit VisionCheckComplete(recordId, passed);
        emit StatusUpdated(recordId, record.status);
    }

    /**
     * @dev Registra la recolección por robot
     */
    function setRobotPickup(uint256 recordId)
    external
    whenNotPaused
    recordExists(recordId)
    onlyAuthenticatedOperator
    {
        ManufacturingRecord storage record = records[recordId];
        require(record.visionVerified, "Vision not verified");
        require(!record.robotPickupComplete, "Robot pickup already complete");

        record.robotPickupComplete = true;
        record.status = "ROBOT_PICKUP_COMPLETE";

        emit RobotPickupComplete(recordId);
        emit StatusUpdated(recordId, record.status);
    }

    /**
     * @dev Registra el ensamblaje completado
     */
    function setAssemblyComplete(uint256 recordId)
    external
    whenNotPaused
    recordExists(recordId)
    onlyAuthenticatedOperator
    {
        ManufacturingRecord storage record = records[recordId];
        require(record.robotPickupComplete, "Robot pickup not complete");
        require(!record.assemblyComplete, "Assembly already complete");

        record.assemblyComplete = true;
        record.completionTime = block.timestamp;
        record.status = "ASSEMBLY_COMPLETE";

        emit AssemblyComplete(recordId);
        emit ManufacturingComplete(recordId, record.completionTime);
        emit StatusUpdated(recordId, record.status);
    }

    /**
     * @dev Obtiene el registro completo de manufactura
     */
    function getManufacturingRecord(uint256 recordId)
    external
    view
    recordExists(recordId)
    returns (ManufacturingRecord memory)
    {
        return records[recordId];
    }

    /**
     * @dev Obtiene el tiempo total de manufactura
     */
    function getManufacturingTime(uint256 recordId)
    external
    view
    recordExists(recordId)
    returns (uint256)
    {
        ManufacturingRecord storage record = records[recordId];
        if (record.completionTime == 0) {
            return block.timestamp - record.startTime;
        }
        return record.completionTime - record.startTime;
    }

    /**
     * @dev Verifica si el proceso está completo
     */
    function isManufacturingComplete(uint256 recordId)
    external
    view
    recordExists(recordId)
    returns (bool)
    {
        return records[recordId].assemblyComplete;
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