/// Heating analytics service — all calculation logic separated from UI.
///
/// Handles heating curve mathematics, savings potential calculations,
/// and efficiency analysis for the Danfoss ECL 310 controller.
library;

import 'dart:math' as math;

/// Calculated heating curve data point for chart rendering.
class HeatingCurvePoint {
  final double outdoorTemp;
  final double flowTarget;

  const HeatingCurvePoint(this.outdoorTemp, this.flowTarget);
}

/// Result of the savings potential analysis.
class SavingsAnalysis {
  /// Current parallel shift setting.
  final double currentShift;

  /// Ideal shift (community benchmark).
  final double idealShift;

  /// Number of steps to reduce.
  final int stepsToFix;

  /// Estimated percentage of energy savings.
  final double savingsPercent;

  /// Estimated Euro savings over the cost basis used ([annualBaseCost]).
  final double annualSavingsEuro;

  /// The cost basis the savings were computed from (actual heating cost when
  /// available, otherwise an estimate).
  final double annualBaseCost;

  /// Whether [annualBaseCost] came from real (synced) Brunata data.
  final bool basedOnActualCost;

  /// Whether the current setting is suboptimal.
  final bool hasOptimizationPotential;

  /// Human-readable advice text.
  final String adviceText;

  const SavingsAnalysis({
    required this.currentShift,
    required this.idealShift,
    required this.stepsToFix,
    required this.savingsPercent,
    required this.annualSavingsEuro,
    required this.annualBaseCost,
    required this.basedOnActualCost,
    required this.hasOptimizationPotential,
    required this.adviceText,
  });
}

/// Pure calculation service — no state, no I/O, no widgets.
///
/// All methods are static for easy testing and zero initialization cost.
abstract final class HeatingAnalyticsService {
  // ──────────────────────────────────────────────────────────────────
  // Constants
  // ──────────────────────────────────────────────────────────────────

  /// Industry rule of thumb: each 1-unit parallel shift reduction
  /// saves approximately 6% of total heat energy.
  static const double savingsPerStep = 0.06;

  /// Community benchmark for ideal parallel shift setting.
  static const double idealShift = 0.0;

  /// Standard radiator heating curve parameters (European norm).
  static const double _designOutdoorTemp = -20.0; // °C
  static const double _designFlowTemp = 75.0; // °C
  static const double _roomTarget = 20.0; // °C
  static const double _curveExponent = 1.33; // Standard radiator

  // ──────────────────────────────────────────────────────────────────
  // Heating Curve Calculation
  // ──────────────────────────────────────────────────────────────────

  /// Calculates the target flow temperature for a given outdoor temperature
  /// and parallel shift using the standard European heating curve formula.
  ///
  /// Formula: flowTarget = roomTarget + (designFlow - roomTarget)
  ///          × ((roomTarget - outdoorTemp) / (roomTarget - designOutdoor))^exponent
  ///          + parallelShift
  ///
  /// Returns the calculated flow target, clamped to [roomTarget, 90°C].
  static double calculateFlowTarget(
    double outdoorTemp, {
    double parallelShift = 0,
  }) {
    // When outdoor >= room target, no heating needed
    if (outdoorTemp >= _roomTarget) {
      return _roomTarget + parallelShift;
    }

    final ratio =
        (_roomTarget - outdoorTemp) / (_roomTarget - _designOutdoorTemp);
    final base = _designFlowTemp - _roomTarget;
    final flowTarget =
        _roomTarget + base * math.pow(ratio.clamp(0, 2), _curveExponent) + parallelShift;

    return flowTarget.clamp(_roomTarget, 90.0);
  }

  /// Generates a series of heating curve data points for chart rendering.
  ///
  /// Returns points from [minOutdoor] to [maxOutdoor] in 1°C steps.
  static List<HeatingCurvePoint> generateHeatingCurve({
    double parallelShift = 0,
    double minOutdoor = -20,
    double maxOutdoor = 20,
  }) {
    final points = <HeatingCurvePoint>[];
    for (double t = minOutdoor; t <= maxOutdoor; t += 1.0) {
      points.add(HeatingCurvePoint(
        t,
        calculateFlowTarget(t, parallelShift: parallelShift),
      ));
    }
    return points;
  }

  // ──────────────────────────────────────────────────────────────────
  // Savings & Efficiency Analysis
  // ──────────────────────────────────────────────────────────────────

  /// Analyzes the savings potential based on the current parallel shift
  /// and the actual heating cost.
  ///
  /// [currentShift]: Current register value for parallel shift.
  /// [annualBaseCost]: Actual heating cost for the billing period in Euros
  /// (year-to-date estimate from Brunata). When 0/unknown a fallback estimate
  /// is used and [SavingsAnalysis.basedOnActualCost] is false.
  static SavingsAnalysis analyzeSavings({
    required double currentShift,
    double annualBaseCost = 0,
  }) {
    final hasActualCost = annualBaseCost > 0;
    // Fallback estimate only when no real cost is available.
    final baseCost = hasActualCost ? annualBaseCost : 1200.0;

    final stepsToFix = (currentShift - idealShift).abs().round();
    final hasPotential = currentShift.abs() > 1;

    // Cap at realistic savings (diminishing returns beyond ~50%)
    final rawSavingsPercent = stepsToFix * savingsPerStep;
    final savingsPercent = rawSavingsPercent.clamp(0.0, 0.50);
    final annualSavings = baseCost * savingsPercent;

    String advice;
    if (!hasPotential) {
      advice = 'Deine Heizungseinstellung ist optimal! '
          'Die Heizkurve läuft im empfohlenen Bereich.';
    } else if (currentShift > 3) {
      advice =
          'Deine Basis-Wärme steht deutlich über dem empfohlenen Durchschnitt. '
          'Durch das Absenken um $stepsToFix Stufen senkst du deine '
          'Vorlauftemperatur effizient. Jedes Grad weniger spart ca. 6% '
          'reine Heizenergie!';
    } else if (currentShift > 0) {
      advice = 'Die Basis-Wärme liegt leicht über dem Optimum. '
          'Eine Absenkung um $stepsToFix Stufe${stepsToFix > 1 ? 'n' : ''} '
          'könnte deine Heizkosten um ca. '
          '${(savingsPercent * 100).round()}% senken.';
    } else if (currentShift < -3) {
      advice = 'Die Basis-Wärme ist sehr niedrig eingestellt. '
          'Falls Räume nicht warm genug werden, erhöhe die '
          'Einstellung schrittweise.';
    } else {
      advice = 'Deine Heizungseinstellung ist nahe am Optimum. '
          'Kleine Anpassungen können noch ${(savingsPercent * 100).round()}% '
          'Einsparung bringen.';
    }

    return SavingsAnalysis(
      currentShift: currentShift,
      idealShift: idealShift,
      stepsToFix: stepsToFix,
      savingsPercent: savingsPercent,
      annualSavingsEuro: annualSavings,
      annualBaseCost: baseCost,
      basedOnActualCost: hasActualCost,
      hasOptimizationPotential: hasPotential,
      adviceText: advice,
    );
  }

  /// Calculates the efficiency delta between flow and return temperatures.
  ///
  /// A healthy delta for residential heating is typically 5–25°C.
  static ({double delta, bool isHealthy, String label}) efficiencyDelta({
    required double flowTemp,
    required double returnTemp,
  }) {
    final delta = flowTemp - returnTemp;
    final isHealthy = delta >= 5 && delta <= 25;
    final label = isHealthy ? 'Optimal' : delta < 5 ? 'Zu gering' : 'Zu hoch';
    return (delta: delta, isHealthy: isHealthy, label: label);
  }
}
