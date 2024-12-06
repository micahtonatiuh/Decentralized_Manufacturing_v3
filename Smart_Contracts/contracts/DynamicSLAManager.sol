// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DynamicSLAManager is Ownable, Pausable, ReentrancyGuard {
    struct SLAMetrics {
        uint256 targetPrintingTime;    // Target time for printing
        uint256 targetQualityScore;    // Target quality score
        uint256 targetPickupTime;      // Target time for pickup
        uint256 targetAssemblyTime;    // Target time for assembly
        uint256 actualPrintingTime;    // Actual printing time
        uint256 actualQualityScore;    // Actual quality score
        uint256 actualPickupTime;      // Actual pickup time
        uint256 actualAssemblyTime;    // Actual assembly time
        bool completed;                // Whether the process is complete
        uint256 performanceScore;      // Overall performance score
    }

    struct AdjustmentFactors {
        uint256 printingWeight;       // Weight for printing time adjustments
        uint256 qualityWeight;        // Weight for quality adjustments
        uint256 pickupWeight;         // Weight for pickup time adjustments
        uint256 assemblyWeight;       // Weight for assembly time adjustments
        uint256 adjustmentThreshold;  // Threshold for making adjustments
    }

    // Constants
    uint256 public constant PERFORMANCE_DECIMALS = 2;
    uint256 public constant MIN_PERFORMANCE_THRESHOLD = 60;
    uint256 public constant MAX_PERFORMANCE_THRESHOLD = 95;
    uint256 public constant MIN_WEIGHT = 1;
    uint256 public constant DEFAULT_HISTORY_LIMIT = 10;
    uint256 public constant BASE_SCORE = 80;
    uint256 public constant MAX_BONUS = 20;
    uint256 public constant BONIFICATION_THRESHOLD = 90;

    // State variables
    uint256 public historyLimit;
    uint256 private currentId;

    // Mappings
    mapping(uint256 => SLAMetrics) public slaMetrics;
    mapping(string => AdjustmentFactors) public adjustmentFactors;
    mapping(string => uint256[]) public manufacturingTypeHistory;

    // Events
    event MetricsAdjusted(
        string manufacturingType,
        uint256 newPrintingTime,
        uint256 newQualityScore,
        uint256 newPickupTime,
        uint256 newAssemblyTime,
        uint256 avgPerformance,
        uint256 adjustmentFactor
    );
    event PerformanceRegistered(uint256 indexed manufacturingId, uint256 performanceScore);
    event HistoryLimitUpdated(uint256 newLimit);
    event BaseMetricsInitialized(
        uint256 targetPrintingTime,
        uint256 targetQualityScore,
        uint256 targetPickupTime,
        uint256 targetAssemblyTime
    );
    event MetricsSet(
        uint256 indexed manufacturingId,
        uint256 actualPrintingTime,
        uint256 actualQualityScore,
        uint256 actualPickupTime,
        uint256 actualAssemblyTime
    );
    event ComponentScores(
        uint256 indexed manufacturingId,
        uint256 printingScore,
        uint256 qualityScore,
        uint256 pickupScore,
        uint256 assemblyScore
    );

    // Errors
    error InvalidParameters();
    error InsufficientHistory();
    error MetricsNotInitialized();

    constructor(address initialOwner) Ownable(initialOwner) {
        historyLimit = DEFAULT_HISTORY_LIMIT;
    }

    function initializeBaseMetrics(
        uint256 targetPrintingTime,
        uint256 targetQualityScore,
        uint256 targetPickupTime,
        uint256 targetAssemblyTime
    ) external onlyOwner
    {

        if (targetPrintingTime == 0 || targetQualityScore == 0 ||
        targetPickupTime == 0 || targetAssemblyTime == 0) revert InvalidParameters();

        SLAMetrics storage baseMetrics = slaMetrics[0];
        baseMetrics.targetPrintingTime = targetPrintingTime;
        baseMetrics.targetQualityScore = targetQualityScore;
        baseMetrics.targetPickupTime = targetPickupTime;
        baseMetrics.targetAssemblyTime = targetAssemblyTime;

        emit BaseMetricsInitialized(
            targetPrintingTime,
            targetQualityScore,
            targetPickupTime,
            targetAssemblyTime
        );
    }

    function setAdjustmentFactors(
        string memory manufacturingType,
        uint256 printingWeight,
        uint256 qualityWeight,
        uint256 pickupWeight,
        uint256 assemblyWeight,
        uint256 threshold
    ) external onlyOwner {
        if (printingWeight < MIN_WEIGHT ||
        qualityWeight < MIN_WEIGHT ||
        pickupWeight < MIN_WEIGHT ||
        assemblyWeight < MIN_WEIGHT ||
        threshold < MIN_PERFORMANCE_THRESHOLD ||
            threshold > MAX_PERFORMANCE_THRESHOLD) revert InvalidParameters();

        adjustmentFactors[manufacturingType] = AdjustmentFactors({
            printingWeight: printingWeight,
            qualityWeight: qualityWeight,
            pickupWeight: pickupWeight,
            assemblyWeight: assemblyWeight,
            adjustmentThreshold: threshold
        });
    }

    function setHistoryLimit(uint256 newLimit) external onlyOwner {
        if (newLimit < 3) revert InvalidParameters();
        historyLimit = newLimit;
        emit HistoryLimitUpdated(newLimit);
    }

    function setMetrics(
        uint256 manufacturingId,
        uint256 actualPrintingTime,
        uint256 actualQualityScore,
        uint256 actualPickupTime,
        uint256 actualAssemblyTime
    ) external onlyOwner {
        if (slaMetrics[0].targetPrintingTime == 0) revert MetricsNotInitialized();
        if (actualQualityScore > 100) revert InvalidParameters();

        // Validate that the times are not 0
        if (actualPrintingTime == 0 || actualPickupTime == 0 || actualAssemblyTime == 0)
            revert InvalidParameters();

        SLAMetrics storage metrics = slaMetrics[manufacturingId];
        SLAMetrics storage baseMetrics = slaMetrics[0];

        // Copy base metrics if they do not exist
        if (metrics.targetPrintingTime == 0) {
            metrics.targetPrintingTime = baseMetrics.targetPrintingTime;
            metrics.targetQualityScore = baseMetrics.targetQualityScore;
            metrics.targetPickupTime = baseMetrics.targetPickupTime;
            metrics.targetAssemblyTime = baseMetrics.targetAssemblyTime;
        }

        metrics.actualPrintingTime = actualPrintingTime;
        metrics.actualQualityScore = actualQualityScore;
        metrics.actualPickupTime = actualPickupTime;
        metrics.actualAssemblyTime = actualAssemblyTime;

        emit MetricsSet(
            manufacturingId,
            actualPrintingTime,
            actualQualityScore,
            actualPickupTime,
            actualAssemblyTime
        );
        currentId++;
    }

    function evaluatePerformance(uint256 manufacturingId)
    external
    whenNotPaused
    nonReentrant
    returns (uint256)
    {
        // Get the individual scores
        SLAMetrics storage metrics = slaMetrics[manufacturingId];
        AdjustmentFactors memory factors = adjustmentFactors["standard_manufacturing"];

        if (factors.printingWeight == 0) {
            factors = adjustmentFactors["default"];
        }

        uint256 printingScore = _calculateComponentScore(
            metrics.actualPrintingTime,
            metrics.targetPrintingTime
        );

        uint256 qualityScore = _calculateQualityScore(
            metrics.actualQualityScore,
            metrics.targetQualityScore
        );

        uint256 pickupScore = _calculateComponentScore(
            metrics.actualPickupTime,
            metrics.targetPickupTime
        );

        uint256 assemblyScore = _calculateComponentScore(
            metrics.actualAssemblyTime,
            metrics.targetAssemblyTime
        );

        // Emit the individual scores
        emit ComponentScores(
            manufacturingId,
            printingScore,
            qualityScore,
            pickupScore,
            assemblyScore
        );

        // Calculate final score
        uint256 performanceScore = _calculateFinalScore(
            printingScore,
            qualityScore,
            pickupScore,
            assemblyScore,
            factors
        );

        metrics.performanceScore = performanceScore;
        metrics.completed = true;

        emit PerformanceRegistered(manufacturingId, performanceScore);
        return performanceScore;
    }

    function calculatePerformanceScore(uint256 manufacturingId)
    public
    view
    returns (uint256)
    {
        SLAMetrics storage metrics = slaMetrics[manufacturingId];
        AdjustmentFactors memory factors = adjustmentFactors["standard_manufacturing"];

        if (factors.printingWeight == 0) {
            factors = adjustmentFactors["default"];
        }
        uint256 totalWeight = factors.printingWeight +
                        factors.qualityWeight +
                        factors.pickupWeight +
                        factors.assemblyWeight;

        if (totalWeight == 0) {
            totalWeight = 4;
            factors.printingWeight = 1;
            factors.qualityWeight = 1;
            factors.pickupWeight = 1;
            factors.assemblyWeight = 1;
        }


        uint256 printingScore = _calculateComponentScore(
            metrics.actualPrintingTime,
            metrics.targetPrintingTime
        );

        uint256 qualityScore = _calculateQualityScore(
            metrics.actualQualityScore,
            metrics.targetQualityScore
        );

        uint256 pickupScore = _calculateComponentScore(
            metrics.actualPickupTime,
            metrics.targetPickupTime
        );

        uint256 assemblyScore = _calculateComponentScore(
            metrics.actualAssemblyTime,
            metrics.targetAssemblyTime
        );

        return _calculateFinalScore(
            printingScore,
            qualityScore,
            pickupScore,
            assemblyScore,
            factors
        );
    }

    function _calculateFinalScore(
        uint256 printingScore,
        uint256 qualityScore,
        uint256 pickupScore,
        uint256 assemblyScore,
        AdjustmentFactors memory factors
    )
    private
    pure
    returns (uint256)
    {
        uint256 totalWeight = factors.printingWeight + factors.qualityWeight +
                        factors.pickupWeight + factors.assemblyWeight;

        if (totalWeight == 0) {
            totalWeight = 4;
            factors.printingWeight = 1;
            factors.qualityWeight = 1;
            factors.pickupWeight = 1;
            factors.assemblyWeight = 1;
        }

        // Calculate weighted final score with high precision
        uint256 weightedScore = (
            (printingScore * factors.printingWeight * 10000) +
            (qualityScore * factors.qualityWeight * 10000) +
            (pickupScore * factors.pickupWeight * 10000) +
            (assemblyScore * factors.assemblyWeight * 10000)
        ) / (totalWeight * 10000);

        return weightedScore;
    }

    function _calculateComponentScore(uint256 actual, uint256 target)
    private
    pure
    returns (uint256)
    {
        // If there's no target, return 0
        if (target == 0) return 0;

        // If actual is 0, return minimum score
        if (actual == 0) return 1;

        // For time metrics (where lower is better)
        if (actual <= target) {
            // Calculate a score between BASE_SCORE and 100 based on how close it is to target
            uint256 improvement = ((target - actual) * MAX_BONUS*1e4) / target;
            return BASE_SCORE + (improvement/1e4);
        }

        // If exceeds target, calculate penalty
        uint256 excess = ((actual - target) * BASE_SCORE*1e4) / target;
        if (excess >= BASE_SCORE*1e4) return MIN_PERFORMANCE_THRESHOLD; // If exceeds by 100% or more, minimum score

        return BASE_SCORE - (excess/1e4); // Linear penalty based on excess
    }

    function _calculateQualityScore(uint256 actual, uint256 target)
    private
    pure
    returns (uint256)
    {
        // If there's no target, return 0
        if (target == 0) return 0;
        if (actual == 0) return MIN_PERFORMANCE_THRESHOLD;


        // For quality metrics (where higher is better)
        if (actual >= target) {
            // Base score plus up to MAX_BONUS additional points for exceeding target
            uint256 improvement = ((actual - target) * MAX_BONUS) / target;
            if (improvement > MAX_BONUS) improvement = MAX_BONUS;
            return BASE_SCORE + improvement;
        }

        // If target is not reached
        return (actual * BASE_SCORE) / target; // Proportional score up to BASE_SCORE
    }

    function isEligibleForBonification(uint256 manufacturingId) public view returns (bool) {
        SLAMetrics storage metrics = slaMetrics[manufacturingId];
        if (!metrics.completed) return false;

        return metrics.performanceScore >= BONIFICATION_THRESHOLD;
    }

    function getPendingBonificationsOrdered()
    external
    view
    returns (uint256[] memory)
    {
        uint256[] memory pendingIds = new uint256[](historyLimit);
        uint256 count = 0;

        // Collect IDs with scores > BONIFICATION_THRESHOLD
        for (uint256 i = 1; i <= currentId; i++) {
            if (isEligibleForBonification(i)) {
                pendingIds[count++] = i;
            }
        }

        // Sort by descending score
        _sortByScore(pendingIds, count);
        return pendingIds;
    }



    function _sortByScore(uint256[] memory ids, uint256 length) private view {
        for (uint i = 0; i < length - 1; i++) {
            for (uint j = 0; j < length - i - 1; j++) {
                uint256 score1 = calculatePerformanceScore(ids[j]);
                uint256 score2 = calculatePerformanceScore(ids[j + 1]);
                if (score1 < score2) {
                    uint256 temp = ids[j];
                    ids[j] = ids[j + 1];
                    ids[j + 1] = temp;
                }
            }
        }
    }

    function _updateMetricsHistory(string memory manufacturingType, uint256 manufacturingId)
    private
    {
        uint256[] storage history = manufacturingTypeHistory[manufacturingType];

        if (history.length >= historyLimit) {
            // Move elements and delete the oldest element
            for (uint i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history.pop();
        }

        history.push(manufacturingId);
    }

    function _adjustMetrics(string memory manufacturingType)
    private
    {
        uint256[] storage history = manufacturingTypeHistory[manufacturingType];
        if (history.length < 3) revert InsufficientHistory();

        uint256 totalPerformance = 0;
        for (uint i = 0; i < history.length; i++) {
            totalPerformance += slaMetrics[history[i]].performanceScore;
        }

        uint256 avgPerformance = totalPerformance / history.length;
        AdjustmentFactors memory factors = adjustmentFactors[manufacturingType];

        if (factors.adjustmentThreshold == 0) {
            factors = adjustmentFactors["default"];
        }

        _updateTargets(manufacturingType, avgPerformance, factors);
    }

    function _updateTargets(
        string memory manufacturingType,
        uint256 avgPerformance,
        AdjustmentFactors memory factors
    )
    private
    {
        SLAMetrics storage baseMetrics = slaMetrics[0];

        uint256 adjustmentFactor;
        if (avgPerformance < factors.adjustmentThreshold) {
            adjustmentFactor = 105; // Increase targets by 5%
        } else if (avgPerformance > (100 - factors.adjustmentThreshold)) {
            adjustmentFactor = 95;  // Decrease targets by 5%
        } else {
            return; // No adjustment needed
        }

        baseMetrics.targetPrintingTime = (baseMetrics.targetPrintingTime * adjustmentFactor) / 100;
        baseMetrics.targetQualityScore = (baseMetrics.targetQualityScore * adjustmentFactor) / 100;
        baseMetrics.targetPickupTime = (baseMetrics.targetPickupTime * adjustmentFactor) / 100;
        baseMetrics.targetAssemblyTime = (baseMetrics.targetAssemblyTime * adjustmentFactor) / 100;

        emit MetricsAdjusted(
            manufacturingType,
            baseMetrics.targetPrintingTime,
            baseMetrics.targetQualityScore,
            baseMetrics.targetPickupTime,
            baseMetrics.targetAssemblyTime,
            avgPerformance,
            adjustmentFactor
        );
    }

    function pause() external onlyOwner {
        _pause();
    }
}