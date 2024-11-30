
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IIPFSRegistry {
    function processBonification(
        string memory designHash,
        address recipient,
        uint256 amount
    ) external;
    function getDesignDetails(string memory designHash)
    external
    view
    returns (
        bool isRegistered,
        address owner,
        uint256 price,
        uint256 bonificationPool,
        uint256 totalLicenses,
        bool active
    );
}

interface IDynamicSLAManager {
    function evaluatePerformance(uint256 manufacturingId) external returns (uint256);
    function calculatePerformanceScore(uint256 manufacturingId) external view returns (uint256);
}

contract SLAManager is Ownable, Pausable, ReentrancyGuard {
    struct SLAMetrics {
        uint256 targetCompletionTime;
        uint256 maxTemperatureDeviation;
        uint256 minQualityScore;
        uint256 timestamp;
        string manufacturingType;
        string designHash;
        address operator;
        bool isActive;
    }

    struct EvaluationResult {
        bool evaluated;
        bool isCompliant;
        uint256 actualCompletionTime;
        uint256 actualTemperatureDeviation;
        uint256 actualQualityScore;
        bool bonificationPending;
        string[] violations;
    }

    // State variables
    IIPFSRegistry public ipfsRegistry;
    IDynamicSLAManager public dynamicSLAManager;
    mapping(uint256 => SLAMetrics) public slaMetrics;
    mapping(uint256 => EvaluationResult) public evaluations;
    mapping(string => uint256) public defaultMetrics;

    // Constants
    uint256 public constant BONIFICATION_PERCENTAGE = 10;
    uint256 public constant MAX_QUALITY_SCORE = 100;
    uint256 public constant MIN_COMPLETION_TIME = 1;
    uint256 public constant MIN_PERFORMANCE_FOR_BONUS = 90;

    // Events
    event MetricsConfigured(
        uint256 indexed manufacturingId,
        uint256 targetTime,
        uint256 maxTempDev,
        uint256 minQuality,
        string manufacturingType,
        string designHash,
        address operator
    );
    event SLAEvaluated(uint256 indexed manufacturingId, bool isCompliant);
    event BonificationProcessed(uint256 indexed manufacturingId, address indexed operator);
    event DefaultMetricsUpdated(
        string manufacturingType,
        uint256 completionTime,
        uint256 tempDeviation,
        uint256 qualityScore
    );
    event RegistryAddressesUpdated(address indexed ipfsRegistry, address indexed dynamicSLAManager);
    event ViolationsRecorded(uint256 indexed manufacturingId, string[] violations);

    // Errors
    error InvalidParameters();
    error MetricsNotSet();
    error BonificationFailed();
    error NotEvaluated();
    error InvalidAddress();
    error NoPendingBonification();

    constructor(
        address initialOwner,
        address _ipfsRegistry,
        address _dynamicSLAManager
    ) Ownable(initialOwner) {
        if (_ipfsRegistry == address(0) || _dynamicSLAManager == address(0))
            revert InvalidAddress();

        ipfsRegistry = IIPFSRegistry(_ipfsRegistry);
        dynamicSLAManager = IDynamicSLAManager(_dynamicSLAManager);
    }

    modifier canEvaluate(uint256 manufacturingId) {
        require(slaMetrics[manufacturingId].isActive, "Metrics not set");
        _;
    }

    function setDefaultMetrics(
        string memory manufacturingType,
        uint256 completionTime,
        uint256 tempDeviation,
        uint256 qualityScore
    )
    external
    onlyOwner
    whenNotPaused
    {
        if (bytes(manufacturingType).length == 0 ||
        completionTime < MIN_COMPLETION_TIME ||
        qualityScore == 0 ||
            qualityScore > MAX_QUALITY_SCORE) revert InvalidParameters();

        defaultMetrics[manufacturingType] = completionTime;

        emit DefaultMetricsUpdated(
            manufacturingType,
            completionTime,
            tempDeviation,
            qualityScore
        );
    }

    function setSLAMetrics(
        uint256 manufacturingId,
        string memory manufacturingType,
        string memory designHash,
        address operator,
        uint256 completionTime,
        uint256 tempDeviation,
        uint256 qualityScore
    )
    external
    whenNotPaused
    nonReentrant
    {
        if (completionTime < MIN_COMPLETION_TIME ||
        qualityScore == 0 ||
        qualityScore > MAX_QUALITY_SCORE ||
        bytes(designHash).length == 0 ||
        bytes(manufacturingType).length == 0 ||
            operator == address(0)) revert InvalidParameters();

        slaMetrics[manufacturingId] = SLAMetrics({
            targetCompletionTime: completionTime,
            maxTemperatureDeviation: tempDeviation,
            minQualityScore: qualityScore,
            timestamp: block.timestamp,
            manufacturingType: manufacturingType,
            designHash: designHash,
            operator: operator,
            isActive: true
        });

        emit MetricsConfigured(
            manufacturingId,
            completionTime,
            tempDeviation,
            qualityScore,
            manufacturingType,
            designHash,
            operator
        );
    }

    function evaluateSLA(
        uint256 manufacturingId,
        uint256 actualCompletionTime,
        uint256 actualTempDeviation,
        uint256 actualQualityScore
    )
    external
    whenNotPaused
    nonReentrant
    canEvaluate(manufacturingId)
    returns (bool)
    {
        SLAMetrics storage metrics = slaMetrics[manufacturingId];

        bool isCompliant = true;
        string[] memory violations = new string[](3);
        uint256 violationCount = 0;

        if (actualCompletionTime > metrics.targetCompletionTime) {
            isCompliant = false;
            violations[violationCount++] = "Completion time exceeded";
        }
        if (actualTempDeviation > metrics.maxTemperatureDeviation) {
            isCompliant = false;
            violations[violationCount++] = "Temperature deviation exceeded";
        }
        if (actualQualityScore < metrics.minQualityScore) {
            isCompliant = false;
            violations[violationCount++] = "Quality score below minimum";
        }

        evaluations[manufacturingId] = EvaluationResult({
            evaluated: true,
            isCompliant: isCompliant,
            actualCompletionTime: actualCompletionTime,
            actualTemperatureDeviation: actualTempDeviation,
            actualQualityScore: actualQualityScore,
            bonificationPending: !isCompliant,
            violations: violations
        });

        emit SLAEvaluated(manufacturingId, isCompliant);
        if (violationCount > 0) {
            emit ViolationsRecorded(manufacturingId, violations);
        }

        uint256 performanceScore = 0;
        if (address(dynamicSLAManager) != address(0)) {
            try dynamicSLAManager.evaluatePerformance(manufacturingId) returns (uint256 score) {
                performanceScore = score;
            } catch {}
        }

        bool eligibleForBonus = isCompliant && performanceScore >= MIN_PERFORMANCE_FOR_BONUS;

        evaluations[manufacturingId] = EvaluationResult({
            evaluated: true,
            isCompliant: isCompliant,
            actualCompletionTime: actualCompletionTime,
            actualTemperatureDeviation: actualTempDeviation,
            actualQualityScore: actualQualityScore,
            bonificationPending: eligibleForBonus, // *modified
            violations: violations
        });

        return isCompliant;
    }

    function processPendingBonification(uint256 manufacturingId)
    external
    whenNotPaused
    nonReentrant
    {
        uint256 performanceScore = dynamicSLAManager.calculatePerformanceScore(manufacturingId);
        require(performanceScore >= MIN_PERFORMANCE_FOR_BONUS, "Performance below threshold");

        EvaluationResult storage evaluation = evaluations[manufacturingId];
        require(evaluation.evaluated, "Not evaluated");
        require(evaluation.bonificationPending, "No pending bonification");
        require(evaluation.isCompliant, "SLA not met");

        SLAMetrics storage metrics = slaMetrics[manufacturingId];

        // Get design details and calculate bonification
        (bool isRegistered, , uint256 price, , , bool active) = ipfsRegistry.getDesignDetails(metrics.designHash);
        if (!isRegistered || !active || price == 0) revert InvalidParameters();

        uint256 bonificationAmount = (price * BONIFICATION_PERCENTAGE) / 100;

        try ipfsRegistry.processBonification(
            metrics.designHash,
            metrics.operator,
            bonificationAmount
        ) {
            evaluation.bonificationPending = false;
            emit BonificationProcessed(manufacturingId, metrics.operator);
        } catch {
            revert BonificationFailed();
        }
    }

    function updateRegistryAddresses(
        address _ipfsRegistry,
        address _dynamicSLAManager
    ) external onlyOwner {
        if (_ipfsRegistry == address(0) || _dynamicSLAManager == address(0))
            revert InvalidParameters();

        ipfsRegistry = IIPFSRegistry(_ipfsRegistry);
        dynamicSLAManager = IDynamicSLAManager(_dynamicSLAManager);

        emit RegistryAddressesUpdated(_ipfsRegistry, _dynamicSLAManager);
    }

    function getEvaluationDetails(uint256 manufacturingId)
    external
    view
    returns (
        bool evaluated,
        bool isCompliant,
        uint256 completionTime,
        uint256 tempDeviation,
        uint256 qualityScore,
        bool bonificationPending,
        string[] memory violations
    )
    {
        EvaluationResult storage evaluation = evaluations[manufacturingId];
        return (
            evaluation.evaluated,
            evaluation.isCompliant,
            evaluation.actualCompletionTime,
            evaluation.actualTemperatureDeviation,
            evaluation.actualQualityScore,
            evaluation.bonificationPending,
            evaluation.violations
        );
    }

    function getSLAMetrics(uint256 manufacturingId)
    external
    view
    returns (
        uint256 targetTime,
        uint256 maxTempDev,
        uint256 minQuality,
        string memory mfgType,
        string memory designHash,
        address operator,
        bool isActive
    )
    {
        SLAMetrics storage metrics = slaMetrics[manufacturingId];
        return (
            metrics.targetCompletionTime,
            metrics.maxTemperatureDeviation,
            metrics.minQualityScore,
            metrics.manufacturingType,
            metrics.designHash,
            metrics.operator,
            metrics.isActive
        );
    }

    function hasPendingBonification(uint256 manufacturingId)
    external
    view
    returns (bool)
    {
        return evaluations[manufacturingId].bonificationPending;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}