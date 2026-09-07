import 'package:flutter_test/flutter_test.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/services/heating_analytics_service.dart';

void main() {
  group('HeatingAnalyticsService - calculateFlowTarget', () {
    test('calculates flow target for typical winter conditions', () {
      final targetAtZero = HeatingAnalyticsService.calculateFlowTarget(0.0);
      expect(targetAtZero, greaterThan(40.0));
      expect(targetAtZero, lessThan(45.0));
    });

    test('maintains continuity across room target temperature boundary', () {
      const shift = -3.0;
      final targetBelow = HeatingAnalyticsService.calculateFlowTarget(19.9, parallelShift: shift);
      final targetAt = HeatingAnalyticsService.calculateFlowTarget(20.0, parallelShift: shift);
      final targetAbove = HeatingAnalyticsService.calculateFlowTarget(20.1, parallelShift: shift);

      expect((targetBelow - targetAt).abs(), lessThan(0.5));
      expect((targetAt - targetAbove).abs(), lessThan(0.001));
    });

    test('clamps flow target within safe physical bounds (15°C to 90°C)', () {
      final extremeCold = HeatingAnalyticsService.calculateFlowTarget(-40.0, parallelShift: 15.0);
      expect(extremeCold, lessThanOrEqualTo(90.0));

      final extremeWarm = HeatingAnalyticsService.calculateFlowTarget(35.0, parallelShift: -15.0);
      expect(extremeWarm, greaterThanOrEqualTo(15.0));
    });
  });

  group('HeatingAnalyticsService - analyzeSavings', () {
    test('positive shift correctly indicates optimization potential', () {
      final analysis = HeatingAnalyticsService.analyzeSavings(
        currentShift: 3.0,
        annualBaseCost: 1000.0,
      );

      expect(analysis.hasOptimizationPotential, isTrue);
      expect(analysis.stepsToFix, equals(3));
      expect(analysis.savingsPercent, closeTo(0.18, 0.001));
      expect(analysis.annualSavingsEuro, closeTo(180.0, 0.1));
      expect(analysis.basedOnActualCost, isTrue);
    });

    test('neutral shift (0.0) indicates optimal operation', () {
      final analysis = HeatingAnalyticsService.analyzeSavings(
        currentShift: 0.0,
        annualBaseCost: 1000.0,
      );

      expect(analysis.hasOptimizationPotential, isFalse);
      expect(analysis.stepsToFix, equals(0));
      expect(analysis.savingsPercent, equals(0.0));
      expect(analysis.annualSavingsEuro, equals(0.0));
      expect(analysis.adviceText, contains('optimal'));
    });

    test('negative shift (-3.0) recognizes active savings and does NOT prompt to reduce', () {
      final analysis = HeatingAnalyticsService.analyzeSavings(
        currentShift: -3.0,
        annualBaseCost: 1000.0,
      );

      expect(analysis.hasOptimizationPotential, isFalse);
      expect(analysis.stepsToFix, equals(0));
      expect(analysis.savingsPercent, equals(0.0));
      expect(analysis.annualSavingsEuro, equals(0.0));
      expect(analysis.adviceText, contains('Sparbetrieb'));
      expect(analysis.adviceText, contains('sparst bereits'));
    });
  });

  group('HeatingAnalyticsService - efficiencyDelta', () {
    test('evaluates healthy delta', () {
      final result = HeatingAnalyticsService.efficiencyDelta(flowTemp: 55.0, returnTemp: 42.0);
      expect(result.delta, equals(13.0));
      expect(result.isHealthy, isTrue);
      expect(result.label, equals('Optimal'));
    });

    test('evaluates too low delta', () {
      final result = HeatingAnalyticsService.efficiencyDelta(flowTemp: 45.0, returnTemp: 43.0);
      expect(result.delta, equals(2.0));
      expect(result.isHealthy, isFalse);
      expect(result.label, equals('Zu gering'));
    });

    test('evaluates too high delta', () {
      final result = HeatingAnalyticsService.efficiencyDelta(flowTemp: 70.0, returnTemp: 35.0);
      expect(result.delta, equals(35.0));
      expect(result.isHealthy, isFalse);
      expect(result.label, equals('Zu hoch'));
    });
  });

  group('ECLReading - Sensor Disconnection', () {
    test('detects disconnected sensor code (19200)', () {
      final reading = ECLReading(
        parameter: ECLRegisters.outdoorTemp,
        rawValue: ECLRegisters.sensorDisconnected,
        timestamp: DateTime.now(),
      );

      expect(reading.isSensorDisconnected, isTrue);
      expect(reading.formattedValue, equals('Fühler getrennt'));
    });

    test('formats valid sensor reading accurately', () {
      final reading = ECLReading(
        parameter: ECLRegisters.flowTemp,
        rawValue: 4520, // 45.2°C
        timestamp: DateTime.now(),
      );

      expect(reading.isSensorDisconnected, isFalse);
      expect(reading.displayValue, closeTo(45.2, 0.01));
      expect(reading.formattedValue, equals('45.2 °C'));
    });
  });

  group('ECLParameter - Bounds Validation', () {
    test('validates heating curve shift bounds [-15, 15]', () {
      expect(ECLRegisters.heatingCurveShift.validateDisplayValue(0.0), isNull);
      expect(ECLRegisters.heatingCurveShift.validateDisplayValue(15.0), isNull);
      expect(ECLRegisters.heatingCurveShift.validateDisplayValue(-15.0), isNull);
      expect(ECLRegisters.heatingCurveShift.validateDisplayValue(16.0), isNotNull);
      expect(ECLRegisters.heatingCurveShift.validateDisplayValue(-16.0), isNotNull);
    });

    test('rejects writes to read-only parameters', () {
      expect(ECLRegisters.flowTemp.validateDisplayValue(50.0), contains('read-only'));
    });
  });
}
