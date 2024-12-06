// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PrinterRegistry
 * @dev Manages the registration and status of 3D printers in the manufacturing system
 */
contract PrinterRegistry is Ownable, Pausable {
    // Structure to store information for each printer
    struct Printer {
        string printerType;           // "fast" or "slow"
        bool isActive;                // Current printer status
        uint256 maxTemperature;       // Maximum supported temperature
        uint256 minTemperature;       // Minimum supported temperature
        string[] supportedMaterials;  // List of supported materials
        uint256 registrationDate;     // Registration date
        uint256 lastMaintenanceDate;  // Last maintenance date
    }

    // Main mappings
    mapping(string => Printer) public printers;
    mapping(string => mapping(string => bool)) public printerCapabilities;

    // Eventos
    event PrinterRegistered(string indexed printerId, string printerType, uint256 timestamp);
    event PrinterStatusUpdated(string indexed printerId, bool isActive);
    event PrinterRemoved(string indexed printerId, uint256 timestamp);
    event PrinterSpecsUpdated(string indexed printerId, uint256 timestamp);
    event MaintenancePerformed(string indexed printerId, uint256 timestamp);

    /**
     * @dev Constructor that initializes the contract
     * @param initialOwner The address of the initial contract owner
     */
    constructor(address initialOwner) Ownable(initialOwner) Pausable() {
    }

    // Modifiers
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
     * @dev Register a new printer in the system
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
     * @dev Updates the activity status of a printer
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
     * @dev Removes a printer from the registry
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
     * @dev Update the technical specifications of a printer
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

        // Clear past capacities
        for (uint i = 0; i < printer.supportedMaterials.length; i++) {
            printerCapabilities[printerId][printer.supportedMaterials[i]] = false;
        }

        // Maintain new materials and capabilities
        printer.supportedMaterials = newMaterials;
        for (uint i = 0; i < newMaterials.length; i++) {
            printerCapabilities[printerId][newMaterials[i]] = true;
        }

        emit PrinterSpecsUpdated(printerId, block.timestamp);
    }

    /**
     * @dev Records maintenance performed on a printer
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
     * @dev Verify if a printer supports a specific media
     */
    function supportsMaterial(string memory printerId, string memory material)
    external
    view
    returns (bool)
    {
        return printerCapabilities[printerId][material];
    }

    /**
     * @dev Obtains the materials supported by a printer
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
     * @dev Checks if a printer is active and within temperature range
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
     * @dev Pause Contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause Contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}