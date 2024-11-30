// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PrinterRegistry
 * @dev Gestiona el registro y estado de las impresoras 3D en el sistema de manufactura
 */
contract PrinterRegistry is Ownable, Pausable {
    // Estructura para almacenar la información de cada impresora
    struct Printer {
        string printerType;           // "fast" o "slow"
        bool isActive;                // Estado actual de la impresora
        uint256 maxTemperature;       // Temperatura máxima soportada
        uint256 minTemperature;       // Temperatura mínima soportada
        string[] supportedMaterials;  // Lista de materiales soportados
        uint256 registrationDate;     // Fecha de registro
        uint256 lastMaintenanceDate;  // Última fecha de mantenimiento
    }

    // Mappings principales
    mapping(string => Printer) public printers;
    mapping(string => mapping(string => bool)) public printerCapabilities;

    // Eventos
    event PrinterRegistered(string indexed printerId, string printerType, uint256 timestamp);
    event PrinterStatusUpdated(string indexed printerId, bool isActive);
    event PrinterRemoved(string indexed printerId, uint256 timestamp);
    event PrinterSpecsUpdated(string indexed printerId, uint256 timestamp);
    event MaintenancePerformed(string indexed printerId, uint256 timestamp);

    /**
     * @dev Constructor que inicializa el contrato
     * @param initialOwner La dirección del propietario inicial del contrato
     */
    constructor(address initialOwner) Ownable(initialOwner) Pausable() {
    }

    // Modificadores
    modifier printerExists(string memory printerId) {
        require(printers[printerId].registrationDate != 0, "Printer does not exist");
        _;
    }

    modifier validPrinterType(string memory printerType) {
        require(
            keccak256(bytes(printerType)) == keccak256(bytes("fast")) ||
            keccak256(bytes(printerType)) == keccak256(bytes("slow")),
            "Invalid printer type: must be 'fast' or 'slow'"
        );
        _;
    }

    /**
     * @dev Registra una nueva impresora en el sistema
     */
    function registerPrinter(
        string memory printerId,
        string memory printerType,
        uint256 maxTemp,
        uint256 minTemp,
        string[] memory materials
    )
    external
    onlyOwner
    whenNotPaused
    validPrinterType(printerType)
    {
        require(bytes(printerId).length > 0, "Invalid printer ID");
        require(printers[printerId].registrationDate == 0, "Printer already registered");
        require(maxTemp > minTemp, "Invalid temperature range");
        require(materials.length > 0, "Must support at least one material");

        printers[printerId] = Printer({
            printerType: printerType,
            isActive: true,
            maxTemperature: maxTemp,
            minTemperature: minTemp,
            supportedMaterials: materials,
            registrationDate: block.timestamp,
            lastMaintenanceDate: block.timestamp
        });

        for (uint i = 0; i < materials.length; i++) {
            printerCapabilities[printerId][materials[i]] = true;
        }

        emit PrinterRegistered(printerId, printerType, block.timestamp);
    }

    /**
     * @dev Actualiza el estado de actividad de una impresora
     */
    function updatePrinterStatus(string memory printerId, bool isActive)
    external
    onlyOwner
    whenNotPaused
    printerExists(printerId)
    {
        printers[printerId].isActive = isActive;
        emit PrinterStatusUpdated(printerId, isActive);
    }

    /**
     * @dev Elimina una impresora del registro
     */
    function removePrinter(string memory printerId)
    external
    onlyOwner
    whenNotPaused
    printerExists(printerId)
    {
        delete printers[printerId];
        emit PrinterRemoved(printerId, block.timestamp);
    }

    /**
     * @dev Actualiza las especificaciones técnicas de una impresora
     */
    function updatePrinterSpecs(
        string memory printerId,
        uint256 newMaxTemp,
        uint256 newMinTemp,
        string[] memory newMaterials
    )
    external
    onlyOwner
    whenNotPaused
    printerExists(printerId)
    {
        require(newMaxTemp > newMinTemp, "Invalid temperature range");
        require(newMaterials.length > 0, "Must support at least one material");

        Printer storage printer = printers[printerId];
        printer.maxTemperature = newMaxTemp;
        printer.minTemperature = newMinTemp;

        // Limpiar capacidades anteriores
        for (uint i = 0; i < printer.supportedMaterials.length; i++) {
            printerCapabilities[printerId][printer.supportedMaterials[i]] = false;
        }

        // Actualizar nuevos materiales y capacidades
        printer.supportedMaterials = newMaterials;
        for (uint i = 0; i < newMaterials.length; i++) {
            printerCapabilities[printerId][newMaterials[i]] = true;
        }

        emit PrinterSpecsUpdated(printerId, block.timestamp);
    }

    /**
     * @dev Registra mantenimiento realizado a una impresora
     */
    function registerMaintenance(string memory printerId)
    external
    onlyOwner
    whenNotPaused
    printerExists(printerId)
    {
        printers[printerId].lastMaintenanceDate = block.timestamp;
        emit MaintenancePerformed(printerId, block.timestamp);
    }

    /**
     * @dev Verifica si una impresora soporta un material específico
     */
    function supportsMaterial(string memory printerId, string memory material)
    external
    view
    returns (bool)
    {
        return printerCapabilities[printerId][material];
    }

    /**
     * @dev Obtiene los materiales soportados por una impresora
     */
    function getPrinterMaterials(string memory printerId)
    external
    view
    printerExists(printerId)
    returns (string[] memory)
    {
        return printers[printerId].supportedMaterials;
    }

    /**
     * @dev Verifica si una impresora está activa y dentro del rango de temperatura
     */
    function isPrinterOperational(
        string memory printerId,
        uint256 requiredTemp
    )
    external
    view
    returns (bool)
    {
        Printer storage printer = printers[printerId];
        return (
            printer.isActive &&
            requiredTemp >= printer.minTemperature &&
            requiredTemp <= printer.maxTemperature
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