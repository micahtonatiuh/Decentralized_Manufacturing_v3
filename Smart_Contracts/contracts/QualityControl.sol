// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title QualityControl
 * @dev Contract for managing quality control checks in a manufacturing process
 */

contract QualityControl is Ownable, Pausable {
    struct QualityCheck {
        bool dimensionsVerified;
        bool colorVerified;
        bool materialVerified;
        uint256 qualityScore;
        uint256 checkTimestamp;
        address inspector;
        string notes;
    }

    mapping(uint256 => QualityCheck) public qualityChecks;
    uint256 public minimumQualityScore = 80;
    mapping(address => bool) public authorizedInspectors;

    event QualityCheckPassed(uint256 indexed manufacturingId, uint256 qualityScore);
    event QualityCheckFailed(uint256 indexed manufacturingId, string reason);
    event InspectorAuthorized(address indexed inspector);
    event InspectorRemoved(address indexed inspector);
    event MinimumScoreUpdated(uint256 newScore);

    /**
    * @dev Contract constructor
     * @param initialOwner Address of the initial contract owner
     */

    constructor(address initialOwner) Ownable(initialOwner) Pausable() {
    }
    /**
     * @dev Modifier to restrict function access to authorized inspectors
     */
    modifier onlyAuthorizedInspector() {
        require(authorizedInspectors[msg.sender], "Not authorized inspector");
        _;
    }
    /**
     * @dev Authorizes a new quality inspector
     * @param inspector Address of the inspector to authorize
     * @notice Only callable by contract owner
     */

    function authorizeInspector(address inspector) external onlyOwner {
        require(inspector != address(0), "Invalid address");
        require(!authorizedInspectors[inspector], "Already authorized");
        authorizedInspectors[inspector] = true;
        emit InspectorAuthorized(inspector);
    }
    /**
     * @dev Removes authorization from an inspector
     * @param inspector Address of the inspector to remove
     * @notice Only callable by contract owner
     */

    function removeInspector(address inspector) external onlyOwner {
        require(authorizedInspectors[inspector], "Not authorized");
        authorizedInspectors[inspector] = false;
        emit InspectorRemoved(inspector);
    }
    /**
     * @dev Updates the minimum required quality score
     * @param newScore New minimum score (1-100)
     * @notice Only callable by contract owner
     */

    function updateMinimumScore(uint256 newScore) external onlyOwner {
        require(newScore > 0 && newScore <= 100, "Invalid score range");
        minimumQualityScore = newScore;
        emit MinimumScoreUpdated(newScore);
    }
    /**
     * @dev Registers a quality control check for a manufacturing process
     * @param manufacturingId ID of the manufacturing process
     * @param dimensions Whether dimensions meet specifications
     * @param color Whether color meets specifications
     * @param material Whether material meets specifications
     * @param score Quality score (0-100)
     * @param notes Inspector's notes about the check
     */

    function registerQualityCheck(
        uint256 manufacturingId,
        bool dimensions,
        bool color,
        bool material,
        uint256 score,
        string memory notes
    ) external whenNotPaused onlyAuthorizedInspector {
        require(score <= 100, "Score must be <= 100");
        require(bytes(notes).length > 0, "Notes required");

        qualityChecks[manufacturingId] = QualityCheck({
            dimensionsVerified: dimensions,
            colorVerified: color,
            materialVerified: material,
            qualityScore: score,
            checkTimestamp: block.timestamp,
            inspector: msg.sender,
            notes: notes
        });

        if (score >= minimumQualityScore && dimensions && color && material) {
            emit QualityCheckPassed(manufacturingId, score);
        } else {
            emit QualityCheckFailed(manufacturingId, "Failed quality standards");
        }
    }
    /**
    * @dev Retrieves quality check details for a manufacturing process
     * @param manufacturingId ID of the manufacturing process
     * @return dimensions Whether dimensions were verified
     * @return color Whether color was verified
     * @return material Whether material was verified
     * @return score Quality score
     * @return timestamp Time of the check
     * @return inspector Address of the inspector
     * @return notes Inspector's notes
     */

    function getQualityCheck(uint256 manufacturingId)
    external
    view
    returns (bool dimensions, bool color, bool material, uint256 score, uint256 timestamp, address inspector, string memory notes)
    {
        QualityCheck storage check = qualityChecks[manufacturingId];
        return (
            check.dimensionsVerified,
            check.colorVerified,
            check.materialVerified,
            check.qualityScore,
            check.checkTimestamp,
            check.inspector,
            check.notes
        );
    }
    /**
     * @dev Checks if a manufacturing process passed quality control
     * @param manufacturingId ID of the manufacturing process
     * @return bool Whether the process passed quality control
     */

    function passedQualityControl(uint256 manufacturingId) external view returns (bool) {
        QualityCheck storage check = qualityChecks[manufacturingId];
        return (
            check.dimensionsVerified &&
            check.colorVerified &&
            check.materialVerified &&
            check.qualityScore >= minimumQualityScore
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}