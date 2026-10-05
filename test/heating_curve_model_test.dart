import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/models/brunata_chart.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
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

  group('Last 12 months heating consumption (Brunata monthly chart)', () {
    BrunataMeterData data(List<BrunataChart> charts) => BrunataMeterData(
          currentBillingPeriodCost: 0,
          consumedKwh: 0,
          communityComparisonPercentage: 0,
          periodStart: DateTime(2026),
          periodEnd: DateTime(2026, 12, 31),
          pricePerKwh: 0.12,
          charts: charts,
        );

    BrunataChart monthly(List<BrunataChartSeries> series) => BrunataChart(
          source: 'month_heizung',
          title: 'Monatsvergleich Heizung',
          subtitle: '',
          unit: 'Verbrauch in kWh',
          categories: const [],
          series: series,
        );

    test('current real months + previous period for the rest', () {
      // Jan–Sep 2026 measured, Oct–Dec extrapolated
      final current = BrunataChartSeries(
        name: '2026',
        values: const [1000, 900, 700, 400, 200, 50, 0, 0, 100, 999, 999, 999],
        extrapolated: const [false, false, false, false, false, false, false, false, false, true, true, true],
      );
      final previous = BrunataChartSeries(
        name: '2025',
        values: const [1100, 950, 750, 450, 250, 60, 10, 0, 120, 400, 700, 950],
        extrapolated: const [false, false, false, false, false, false, false, false, false, false, false, false],
      );
      // 3350 (Jan–Sep 2026) + 400 + 700 + 950 (Oct–Dec 2025) = 5400
      expect(data([monthly([current, previous])]).heatingLast12MonthsKwh, 5400);
    });

    test('null without a previous period (falls back to the projection)', () {
      final current = BrunataChartSeries(
        name: '2026', values: const [1000, 900], extrapolated: const [false, true]);
      expect(data([monthly([current])]).heatingLast12MonthsKwh, isNull);
      expect(data(const []).heatingLast12MonthsKwh, isNull);
    });
  });

  testWidgets('savings table lists −0.5/−1/−2 °C with kWh and €', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HeatingSimulationCard(
            curve: ControllerHeatingCurve.fromReadings(readingsFrom(realController()))!,
            roomSetpoint: 22,
            previewSetpoint: null,
            outdoorTemp: 5,
            annualHeatingKwh: 10000,
            annualHeatingKwhSource: 'Verbrauch der letzten 12 Monate (Brunata Hamburg)',
            pricePerKwh: 0.12,
          ),
        ),
      ),
    ));
    expect(find.text('Was kann ich sparen?'), findsOneWidget);
    expect(find.text('21.0 °C (−1.0)'), findsOneWidget);
    expect(find.text('−600 kWh (6 %)'), findsOneWidget);
    expect(find.text('−72 €'), findsOneWidget);
    expect(find.text('−1200 kWh (12 %)'), findsOneWidget);
    expect(find.textContaining('letzten 12 Monate'), findsOneWidget);
  });

  group('Reference curves', () {
    test('Danfoss factory curve (slope 1.0) incl. room correction', () {
      expect(danfossFactoryCurve.flowAt(0, 20), 45);
      expect(danfossFactoryCurve.flowAt(0, 22), 50); // +2 × 1.0 × 2.5
    });

    test('EnergieSchweiz guide band: values at −8/+15 °C, linear between', () {
      const r = BuildingReference.radiator2000to2010;
      expect(r.lowAt(-8), 40);
      expect(r.highAt(-8), 50);
      expect(r.lowAt(15), 25);
      expect(r.lowAt(3.5), closeTo(32.5, 1e-9));
      expect(r.highAt(20), 25); // flat above +15 °C
      expect(BuildingReference.fromName('floorAfter2010'), BuildingReference.floorAfter2010);
      expect(BuildingReference.fromName('nope'), isNull);
    });
  });

  testWidgets('verdict compares the real curve with the guide band at −8 °C', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HeatingSimulationCard(
            curve: ControllerHeatingCurve.fromReadings(readingsFrom(realController()))!,
            roomSetpoint: 22,
            previewSetpoint: null,
            outdoorTemp: 5,
            annualHeatingKwh: null,
            annualHeatingKwhSource: null,
            pricePerKwh: null,
            buildingReference: BuildingReference.radiator2000to2010,
          ),
        ),
      ),
    ));
    // real curve at −8 °C, 20 °C room: 36 + 0.7 × (32 − 36) = 33.2 °C
    expect(find.textContaining('liefert deine Kurve 33 °C'), findsOneWidget);
    expect(find.textContaining('unter dem Richtwert (40–50 °C)'), findsOneWidget);
    expect(find.text('Danfoss-Werkseinstellung'), findsOneWidget);
    expect(find.text('Richtwert EnergieSchweiz'), findsOneWidget);
  });

  test('floor heating: longer observation, factory curve labelled for radiators', () {
    expect(BuildingReference.floor1990to2010.isFloorHeating, isTrue);
    expect(BuildingReference.radiatorAfter2010.isFloorHeating, isFalse);
    expect(CurveOptimizerService.observationFor(BuildingReference.floorAfter2010), const Duration(hours: 96));
    expect(CurveOptimizerService.observationFor(null), const Duration(hours: 48));
    final s = CurveOptimizerService.started(from: 22, firstStep: 21.5, now: DateTime(2026, 10, 6));
    final day3 = DateTime(2026, 10, 9);
    expect(CurveOptimizerService.phaseOf(s, day3), OptimizerPhase.readyForFeedback);
    expect(CurveOptimizerService.phaseOf(s, day3, wait: const Duration(hours: 96)), OptimizerPhase.waiting);
  });

  group('Brunata Δ % comparison', () {
    BrunataChart chart(String title, List<BrunataChartSeries> series, {String source = ''}) => BrunataChart(
        source: source, title: title, subtitle: '', unit: 'Verbrauch in kWh', categories: const [], series: series);
    BrunataChartSeries ser(String name, List<double> v, [List<bool>? x]) =>
        BrunataChartSeries(name: name, values: v, extrapolated: x ?? List.filled(v.length, false));

    test('building comparison: own flat vs. average, regardless of order', () {
      final c = chart('Liegenschaftsvergleich Heizung', [
        ser('Liegenschafts-Schnitt', [100, 200]),
        ser('Meine Wohnung', [90, 220]),
      ], source: 'liegenschaft_heizung');
      final cmp = c.comparison!;
      expect(cmp.kind, BrunataComparisonKind.buildingAverage);
      expect(cmp.subject.name, 'Meine Wohnung');
      expect(cmp.percentAt(0), closeTo(-10, 1e-9));
      expect(cmp.percentAt(1), closeTo(10, 1e-9));
      expect(cmp.totalPercent, closeTo(10 / 300 * 100, 1e-9));
      expect(calculateCommunityComparisonPercentage([c]), closeTo(3.33, 0.01));
    });

    test('monthly comparison: current year (with extrapolation) vs. previous year', () {
      final c = chart('Monatsvergleich Heizung', [
        ser('2025', [1000, 800, 600]),
        ser('2026', [900, 880, 999], [false, false, true]),
      ], source: 'month_heizung');
      final cmp = c.comparison!;
      expect(cmp.kind, BrunataComparisonKind.previousPeriod);
      expect(cmp.subject.name, '2026');
      expect(cmp.label, 'Δ vs. Vorjahr');
      expect(cmp.percentAt(0), closeTo(-10, 1e-9));
      expect(cmp.percentAt(2), isNull); // extrapolated month
      expect(cmp.totalPercent, closeTo((1780 - 1800) / 1800 * 100, 1e-9)); // measured months only
      // a year-over-year change is never reported as a building comparison
      expect(calculateCommunityComparisonPercentage([c]), isNull);
    });

    test('years without extrapolation: newest year is compared with the previous one', () {
      final cmp = chart('Jahresvergleich', [ser('Abrechnung 2024', [10]), ser('Abrechnung 2025', [12])]).comparison!;
      expect(cmp.subject.name, 'Abrechnung 2025');
      expect(cmp.percentAt(0), closeTo(20, 1e-9));
    });
  });
}
