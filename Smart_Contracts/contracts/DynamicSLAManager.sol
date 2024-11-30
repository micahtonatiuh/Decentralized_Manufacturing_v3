// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DynamicSLAManager is Ownable, Pausable, ReentrancyGuard {
    struct SLAMetrics {
        uint256 targetPrintingTime;    // Tiempo objetivo para impresión
        uint256 targetQualityScore;    // Score objetivo de calidad
        uint256 targetPickupTime;      // Tiempo objetivo para recolección
        uint256 targetAssemblyTime;    // Tiempo objetivo para ensamblaje
        uint256 actualPrintingTime;    // Tiempo real de impresión
        uint256 actualQualityScore;    // Score real de calidad
        uint256 actualPickupTime;      // Tiempo real de recolección
        uint256 actualAssemblyTime;    // Tiempo real de ensamblaje
        bool completed;                // Si el proceso está completo
        uint256 performanceScore;      // Score general de rendimiento
    }

    struct AdjustmentFactors {
        uint256 printingWeight;       // Peso para ajustes de tiempo de impresión
        uint256 qualityWeight;        // Peso para ajustes de calidad
        uint256 pickupWeight;         // Peso para ajustes de tiempo de recolección
        uint256 assemblyWeight;       // Peso para ajustes de tiempo de ensamblaje
        uint256 adjustmentThreshold;  // Umbral para realizar ajustes
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
        uint256 avgPerformance,     // Añadir performance promedio
        uint256 adjustmentFactor    // Añadir factor de ajuste usado
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

        // Validar que los tiempos no sean 0
        if (actualPrintingTime == 0 || actualPickupTime == 0 || actualAssemblyTime == 0)
            revert InvalidParameters();

        SLAMetrics storage metrics = slaMetrics[manufacturingId];
        SLAMetrics storage baseMetrics = slaMetrics[0];

        // Copiar métricas base si no existen
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
        // Obtener los scores individuales
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

        // Emitir los scores individuales
        emit ComponentScores(
            manufacturingId,
            printingScore,
            qualityScore,
            pickupScore,
            assemblyScore
        );

        // Calcular score final
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

        // Calcular score final ponderado con alta precisión
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
        // Si no hay target, retornar 0
        if (target == 0) return 0;

        // Si actual es 0, retornar puntaje mínimo
        if (actual == 0) return 1;

        // Para métricas de tiempo (donde menor es mejor)
        if (actual <= target) {
            // Calculamos un score entre BASE_SCORE y 100 basado en qué tan cerca está del target
            uint256 improvement = ((target - actual) * MAX_BONUS*1e4) / target;
            return BASE_SCORE + (improvement/1e4);
        }

        // Si excede el target, calcular penalización
        uint256 excess = ((actual - target) * BASE_SCORE*1e4) / target;
        if (excess >= BASE_SCORE*1e4) return MIN_PERFORMANCE_THRESHOLD; // Si excede en 100% o más, score mínimo

        return BASE_SCORE - (excess/1e4); // Penalización lineal basada en el exceso
    }

    function _calculateQualityScore(uint256 actual, uint256 target)
    private
    pure
    returns (uint256)
    {
        // Si no hay target, retornar 0
        if (target == 0) return 0;
        if (actual == 0) return MIN_PERFORMANCE_THRESHOLD;


        // Para calidad (donde mayor es mejor)
        if (actual >= target) {
            // Score base más hasta MAX_BONUS puntos adicionales por superar el target
            uint256 improvement = ((actual - target) * MAX_BONUS) / target;
            if (improvement > MAX_BONUS) improvement = MAX_BONUS;
            return BASE_SCORE + improvement;
        }

        // Si no alcanza el target
        return (actual * BASE_SCORE) / target; // Score proporcional hasta BASE_SCORE
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

        // Recolectar IDs con scores > BONIFICATION_THRESHOLD
        for (uint256 i = 1; i <= currentId; i++) {
            if (isEligibleForBonification(i)) {
                pendingIds[count++] = i;
            }
        }

        // Ordenar por score descendente
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
            // Desplazar elementos y eliminar el más antiguo
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