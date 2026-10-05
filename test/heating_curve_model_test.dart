import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/services/curve_optimizer_service.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/widgets/analysis_section.dart';

/// Values read from a real ECL Comfort 310 on 2026-10-05.
const realPoints = [40.0, 36.0, 32.0, 29.0, 26.0, 22.0];

ECLReading? Function(ECLParameter) readingsFrom(Map<String, double> values) => (p) {
      final v = values[p.id];
      return v == null ? null : ECLReading(parameter: p, rawValue: p.displayToRaw(v), timestamp: DateTime(2026));
    };

Map<String, double> realController() => {
      for (var i = 0; i < 6; i++) ECLRegisters.curvePoints[i].id: realPoints[i],
      ECLRegisters.curveSlope.id: 0.5,
      ECLRegisters.curveMinFlow.id: 22,
      ECLRegisters.curveMaxFlow.id: 50,
    };

void main() {
  group('ControllerHeatingCurve', () {
    final curve = ControllerHeatingCurve.fromReadings(readingsFrom(realController()))!;

    test('applies the Danfoss room correction (Sollwert − 20) × Neigung × 2,5', () {
      expect(curve.roomCorrection(22), closeTo(2.5, 1e-9));
      expect(curve.flowAt(0, 20), 29); // point itself at 20 °C room
      expect(curve.flowAt(0, 22), closeTo(31.5, 1e-9));
      expect(curve.flowAt(0, 21) - curve.flowAt(0, 22), closeTo(-1.25, 1e-9));
    });

    test('interpolates between points and stays flat outside them', () {
      expect(curve.flowAt(-10, 20), closeTo(34, 1e-9)); // between -15 (36) and -5 (32)
      expect(curve.flowAt(20, 20), 22); // beyond +15
      expect(curve.flowAt(-40, 20), 40); // beyond -30
    });

    test('respects min/max flow temperature', () {
      expect(curve.flowAt(15, 18), 22); // 22 − 2.5 would be below min 22
      expect(curve.flowAt(-30, 40), 50); // capped at max
    });

    test('is null when the controller does not expose the curve', () {
      final partial = realController()..remove(ECLRegisters.curveSlope.id);
      expect(ControllerHeatingCurve.fromReadings(readingsFrom(partial)), isNull);
    });
  });

  group('RoomTemperatureSavings', () {
    test('about 6 % per °C, with kWh and € when known', () {
      final s = RoomTemperatureSavings.estimate(
        currentSetpoint: 22, newSetpoint: 21, annualHeatingKwh: 8000, pricePerKwh: 0.12);
      expect(s.percent, closeTo(6, 1e-9));
      expect(s.kwhPerYear, closeTo(480, 1e-9));
      expect(s.euroPerYear, closeTo(57.6, 1e-9));
    });

    test('raising the setpoint is shown as extra consumption; unknowns stay null', () {
      final s = RoomTemperatureSavings.estimate(currentSetpoint: 21, newSetpoint: 22);
      expect(s.percent, closeTo(-6, 1e-9));
      expect(s.kwhPerYear, isNull);
      expect(s.euroPerYear, isNull);
    });
  });

  group('CurveOptimizerService', () {
    final t0 = DateTime(2026, 10, 6, 8);

    test('steps down by 0.5 °C and stops at the floor', () {
      expect(CurveOptimizerService.nextStep(22), 21.5);
      expect(CurveOptimizerService.nextStep(18.5), 18.0);
      expect(CurveOptimizerService.nextStep(18.0), isNull);
    });

    test('waits two days before asking for feedback', () {
      final s = CurveOptimizerService.started(from: 22, firstStep: 21.5, now: t0);
      expect(CurveOptimizerService.phaseOf(s, t0.add(const Duration(hours: 47))), OptimizerPhase.waiting);
      expect(CurveOptimizerService.phaseOf(s, t0.add(const Duration(hours: 48))), OptimizerPhase.readyForFeedback);
    });

    test('comfortable continues, too cold returns the previous step as result', () {
      var s = CurveOptimizerService.started(from: 22, firstStep: 21.5, now: t0);
      s = CurveOptimizerService.comfortable(s, nextSetpoint: 21.0, now: t0);
      expect(s.currentSetpoint, 21.0);
      expect(s.previousSetpoint, 21.5);

      final done = CurveOptimizerService.tooCold(s);
      expect(done.resultSetpoint, 21.5);
      expect(done.startSetpoint, 22);
      expect(CurveOptimizerService.phaseOf(done, t0), OptimizerPhase.finished);
    });

    test('state survives a restart', () async {
      final store = <String, String>{};
      final svc = CurveOptimizerService(inMemoryStorage: store);
      await svc.save(CurveOptimizerService.started(from: 22, firstStep: 21.5, now: t0));
      final loaded = await CurveOptimizerService(inMemoryStorage: store).load();
      expect(loaded.currentSetpoint, 21.5);
      expect(loaded.stepStartedAt, t0);
    });
  });

  group('AnalysisSection with the controller curve', () {
    Widget build({double? preview}) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisSection(
                currentOutdoorTemp: 5,
                currentFlowTemp: 30,
                currentReturnTemp: 25,
                parallelShift: 0,
                controllerCurve: ControllerHeatingCurve.fromReadings(readingsFrom(realController())),
                roomSetpoint: 22,
                previewSetpoint: preview,
                annualHeatingKwh: 8000,
                annualHeatingKwhSource: 'eigener Wert',
                pricePerKwh: 0.12,
              ),
            ),
          ),
        );

    testWidgets('shows the real curve and no preview by default', (tester) async {
      await tester.pumpWidget(build());
      expect(find.byKey(const Key('controllerCurveSection')), findsOneWidget);
      expect(find.textContaining('Bewege oben'), findsOneWidget);
      expect(find.textContaining('kWh/Jahr'), findsNothing);
    });

    testWidgets('slider preview shows the new flow and kWh/€ per year', (tester) async {
      await tester.pumpWidget(build(preview: 21));
      // 5 °C outdoor: 26 + 2.5 = 28.5 now, 26 + 1.25 = 27.25 at 21 °C
      expect(find.textContaining('28.5 → 27.3'), findsOneWidget);
      expect(find.textContaining('ca. 6 % weniger Heizenergie · ≈ 480 kWh/Jahr · ≈ 58 €/Jahr'), findsOneWidget);
    });
  });
}
