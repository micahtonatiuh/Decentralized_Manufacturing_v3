// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title RobotControl
 * @dev Controls the operations of robots in the manufacturing process
 */
contract RobotControl is Ownable, Pausable {
    struct RobotOperation {
        bool pickupStarted;
        bool pickupCompleted;
        bool assemblyStarted;
        bool assemblyCompleted;
        uint256 startTime;
        uint256 completionTime;
        string robotId;
        string status;
        uint256[] coordinates;
    }

    // Mappings
    mapping(uint256 => RobotOperation) public operations;
    mapping(string => bool) public authorizedRobots;
    mapping(uint256 => mapping(string => bool)) public manufacturingRobotAssignments;

    // Events
    event PickupStarted(uint256 indexed manufacturingId, string robotId);
    event PickupCompleted(uint256 indexed manufacturingId, string robotId);
    event AssemblyStarted(uint256 indexed manufacturingId, string robotId);
    event AssemblyCompleted(uint256 indexed manufacturingId, string robotId);
    event RobotAuthorized(string robotId);
    event RobotDeauthorized(string robotId);
    event CoordinatesUpdated(uint256 indexed manufacturingId, uint256[] coordinates);

    /**
     * @dev Constructor
     */
    constructor(address initialOwner) Ownable(initialOwner) Pausable() {
    }

    // Modifiers
    modifier onlyAuthorizedRobot(string memory robotId) {
        require(authorizedRobots[robotId], "Robot not authorized");
        _;
    }

    modifier operationExists(uint256 manufacturingId) {
        require(operations[manufacturingId].startTime != 0, "Operation does not exist");
        _;
    }

    /**
     * @dev Authorize a robot
     */
    function authorizeRobot(string memory robotId) external onlyOwner {
        require(bytes(robotId).length > 0, "Invalid robot ID");
        require(!authorizedRobots[robotId], "Robot already authorized");
        authorizedRobots[robotId] = true;
        emit RobotAuthorized(robotId);
    }

    /**
     * @dev Deauthorize a robot
     */
    function deauthorizeRobot(string memory robotId) external onlyOwner {
        require(authorizedRobots[robotId], "Robot not authorized");
        authorizedRobots[robotId] = false;
        emit RobotDeauthorized(robotId);
    }

    /**
     * @dev Start pickup operation
     */
    function startPickup(
        uint256 manufacturingId,
        string memory robotId,
        uint256[] memory coordinates
    )
    external
    whenNotPaused
    onlyAuthorizedRobot(robotId)
    {
        require(coordinates.length > 0, "Invalid coordinates");
        require(!operations[manufacturingId].pickupStarted, "Pickup already started");

        operations[manufacturingId].pickupStarted = true;
        operations[manufacturingId].startTime = block.timestamp;
        operations[manufacturingId].robotId = robotId;
        operations[manufacturingId].coordinates = coordinates;
        operations[manufacturingId].status = "PICKUP_STARTED";

        manufacturingRobotAssignments[manufacturingId][robotId] = true;

        emit PickupStarted(manufacturingId, robotId);
        emit CoordinatesUpdated(manufacturingId, coordinates);
    }

    /**
     * @dev Complete pickup operation
     */
    function completePickup(uint256 manufacturingId)
    external
    whenNotPaused
    operationExists(manufacturingId)
    onlyAuthorizedRobot(operations[manufacturingId].robotId)
    {
        RobotOperation storage operation = operations[manufacturingId];
        require(operation.pickupStarted, "Pickup not started");
        require(!operation.pickupCompleted, "Pickup already completed");

        operation.pickupCompleted = true;
        operation.status = "PICKUP_COMPLETED";

        emit PickupCompleted(manufacturingId, operation.robotId);
    }

    /**
     * @dev Start assembly operation
     */
    function startAssembly(uint256 manufacturingId)
    external
    whenNotPaused
    operationExists(manufacturingId)
    onlyAuthorizedRobot(operations[manufacturingId].robotId)
    {
        RobotOperation storage operation = operations[manufacturingId];
        require(operation.pickupCompleted, "Pickup not completed");
        require(!operation.assemblyStarted, "Assembly already started");

        operation.assemblyStarted = true;
        operation.status = "ASSEMBLY_STARTED";

        emit AssemblyStarted(manufacturingId, operation.robotId);
    }

    /**
     * @dev Complete assembly operation
     */
    function completeAssembly(uint256 manufacturingId)
    external
    whenNotPaused
    operationExists(manufacturingId)
    onlyAuthorizedRobot(operations[manufacturingId].robotId)
    {
        RobotOperation storage operation = operations[manufacturingId];
        require(operation.assemblyStarted, "Assembly not started");
        require(!operation.assemblyCompleted, "Assembly already completed");

        operation.assemblyCompleted = true;
        operation.completionTime = block.timestamp;
        operation.status = "ASSEMBLY_COMPLETED";

        emit AssemblyCompleted(manufacturingId, operation.robotId);
    }

    /**
     * @dev Update robot coordinates
     */
    function updateCoordinates(uint256 manufacturingId, uint256[] memory newCoordinates)
    external
    whenNotPaused
    operationExists(manufacturingId)
    onlyAuthorizedRobot(operations[manufacturingId].robotId)
    {
        require(newCoordinates.length > 0, "Invalid coordinates");
        operations[manufacturingId].coordinates = newCoordinates;
        emit CoordinatesUpdated(manufacturingId, newCoordinates);
    }

    /**
     * @dev Get operation details
     */
    function getOperationDetails(uint256 manufacturingId)
    external
    view
    returns (
        bool pickup,
        bool assemblyState,
        uint256 startTime,
        uint256 completionTime,
        string memory robotId,
        string memory status,
        uint256[] memory coordinates
    )
    {
        RobotOperation storage operation = operations[manufacturingId];
        return (
            operation.pickupCompleted,
            operation.assemblyCompleted,
            operation.startTime,
            operation.completionTime,
            operation.robotId,
            operation.status,
            operation.coordinates
        );
    }

    /**
     * @dev Check if robot is assigned to manufacturing process
     */
    function isRobotAssigned(uint256 manufacturingId, string memory robotId)
    external
    view
    returns (bool)
    {
        return manufacturingRobotAssignments[manufacturingId][robotId];
    }

    /**
     * @dev Calculate operation duration
     */
    function getOperationDuration(uint256 manufacturingId)
    external
    view
    returns (uint256)
    {
        RobotOperation storage operation = operations[manufacturingId];
        require(operation.startTime != 0, "Operation not started");

        if (operation.completionTime == 0) {
            return block.timestamp - operation.startTime;
        }
        return operation.completionTime - operation.startTime;
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}