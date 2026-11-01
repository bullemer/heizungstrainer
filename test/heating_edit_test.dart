import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/widgets/controller_schedule_card.dart';
import 'package:heizungstrainer/widgets/curve_editor_dialog.dart';
import 'package:heizungstrainer/widgets/schedule_day_editor.dart';

/// Records writes instead of sending them to a controller.
class _RecordingProvider extends ECLProvider {
  _RecordingProvider()
      : super(logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false), autoLoadDatabase: false);

  final scheduleWrites = <(int, List<SchedulePeriod>)>[];
  final parameterWrites = <(String, double)>[];

  @override
  bool get supportsControllerSchedule => true;

  @override
  Future<void> writeScheduleDay(int day, List<SchedulePeriod> periods) async {
    scheduleWrites.add((day, periods));
    setControllerScheduleForTesting(controllerSchedule!.withDay(day, periods));
  }

  @override
  Future<ECLReading> writeParameter(ECLParameter parameter, double value) async {
    parameterWrites.add((parameter.id, value));
    setReadingForTesting(parameter, value);
    return getReading(parameter)!;
  }

  @override
  Future<void> refreshReadings() async {}
}

void _setFactoryCurve(ECLProvider p) {
  p.setReadingForTesting(ECLRegisters.curveSlope, danfossFactoryCurve.slope);
  for (var i = 0; i < ECLRegisters.curvePoints.length; i++) {
    p.setReadingForTesting(ECLRegisters.curvePoints[i], danfossFactoryCurve.flowTemps[i]);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('schedule day: chronological, unused at the end, overlaps and midnight refused', () {
    expect(
      normalizeScheduleDay(const [SchedulePeriod(1700, 2200), SchedulePeriod.unused, SchedulePeriod(600, 900)]),
      const [SchedulePeriod(600, 900), SchedulePeriod(1700, 2200), SchedulePeriod.unused],
    );
    expect(scheduleDayError(const [SchedulePeriod(600, 1000), SchedulePeriod(900, 1200), SchedulePeriod.unused]),
        'Die Zeiträume überschneiden sich.');
    expect(scheduleDayError(const [SchedulePeriod(2200, 600), SchedulePeriod.unused, SchedulePeriod.unused]),
        contains('Mitternacht'));
    expect(scheduleDayError(const [SchedulePeriod.allDay, SchedulePeriod.unused, SchedulePeriod.unused]), isNull);
  });

  /// The user's own curve (slope 0.5 with individually set points).
  void setUserCurve(ECLProvider p) {
    p.setReadingForTesting(ECLRegisters.curveSlope, 0.5);
    const points = <double>[40, 36, 32, 29, 26, 22];
    for (var i = 0; i < points.length; i++) {
      p.setReadingForTesting(ECLRegisters.curvePoints[i], points[i]);
    }
  }

  test('scaling keeps the shape around 20 °C and rounds to whole degrees', () {
    final provider = _RecordingProvider();
    setUserCurve(provider);
    final curve = ControllerHeatingCurve.fromReadings(provider.getReading)!;
    expect(curve.scaled(0.9).flowTemps, [38, 34, 31, 28, 25, 22]);
    expect(curve.scaled(1.1).flowTemps, [42, 38, 33, 30, 27, 22]);
    expect(curve.scaled(0.9).slope, 0.5); // slope register untouched
    provider.dispose();
  });

  test('the slope is read only; curve points are refused without a connected Danfoss ECL', () async {
    expect(ECLRegisters.curveSlope.isWritable, isFalse);
    final provider = ECLProvider(
      logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
      autoLoadDatabase: false,
    )..setConnectedForTesting(ip: '192.168.0.2');
    await expectLater(
        provider.writeParameter(ECLRegisters.curvePoints.last, 21), throwsA(isA<ModbusCommunicationException>()));
    provider.dispose();
  });

  test('writeHeatingCurve: only changed points, falling curve after every write', () async {
    final provider = _RecordingProvider();
    setUserCurve(provider);
    await provider.writeHeatingCurve([38, 34, 31, 28, 25, 22]);
    // lowering starts at the warm end; +15 °C (22) is unchanged and skipped
    expect(provider.parameterWrites.map((w) => w.$1).toList(),
        [for (final i in [4, 3, 2, 1, 0]) ECLRegisters.curvePoints[i].id]);

    provider.parameterWrites.clear();
    await provider.writeHeatingCurve([40, 36, 32, 29, 26, 22]);
    expect(provider.parameterWrites.first.$1, ECLRegisters.curvePoints.first.id); // raising: cold end first

    await expectLater(provider.writeHeatingCurve([30, 36, 32, 29, 26, 22]), throwsA(isA<ModbusCommunicationException>()));
    provider.dispose();
  });

  testWidgets('schedule card: tap a day, apply to all → only differing days are written', (tester) async {
    final provider = _RecordingProvider()
      ..setReadingForTesting(ECLRegisters.roomTargetTemp, 21)
      ..setReadingForTesting(ECLRegisters.savingRoomTemp, 18)
      ..setControllerScheduleForTesting(WeekSchedule.fromRaw([
        [2400, 2400, 2400, 2400, 2400, 2400],
        for (var d = 1; d < 7; d++) [0, 2400, 2400, 2400, 2400, 2400],
      ]));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(listenable: provider, builder: (_, _) => ControllerScheduleCard(provider: provider)),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('scheduleDay_1')));
    await tester.pumpAndSettle();
    expect(find.text('Komfortzeiten Dienstag'), findsOneWidget);
    await tester.tap(find.byKey(const Key('applyToAllDays')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveScheduleDay')));
    await tester.pumpAndSettle();

    expect(provider.scheduleWrites.map((w) => w.$1), [0]); // Monday only
    expect(provider.scheduleWrites.single.$2.first, SchedulePeriod.allDay);
    expect(find.text('Komfort 00:00–24:00'), findsNWidgets(7));

    // the saving setpoint chip opens its editor
    await tester.tap(find.byKey(const Key('editSaving')));
    await tester.pumpAndSettle();
    expect(find.text('Spar-Sollwert'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('curve dialog: 10 % flatter shows the exact points and writes them', (tester) async {
    final provider = _RecordingProvider()..setReadingForTesting(ECLRegisters.roomTargetTemp, 20.5);
    setUserCurve(provider);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showCurveEditor(context, provider), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Heizkurve anpassen'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('saveCurve'))).onPressed, isNull); // unchanged

    await tester.tap(find.byKey(const Key('curveFlatter')));
    await tester.tap(find.byKey(const Key('curveFlatter')));
    await tester.pump();
    expect(find.text('10 % flacher'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('curvePoint_0'))).data, '38 °C');
    await tester.tap(find.byKey(const Key('saveCurve')));
    await tester.pumpAndSettle();

    expect(provider.parameterWrites.map((w) => w.$2), [25, 28, 31, 34, 38]);
    expect(provider.parameterWrites.any((w) => w.$1 == ECLRegisters.curveSlope.id), isFalse);
    expect(find.textContaining('40/36/32/29/26/22 → 38/34/31/28/25/22'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('home: Basis-Wärme and heating curve share one card with the curve editor', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = _RecordingProvider()
      ..setConnectedForTesting(ip: '192.168.0.2')
      ..setReadingForTesting(ECLRegisters.roomTargetTemp, 21)
      ..setReadingForTesting(ECLRegisters.outdoorTemp, 5);
    _setFactoryCurve(provider);
    await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
      value: provider,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump();

    final card = find.byKey(const Key('heatingCurveCard'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Haus Basis-Wärme')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Heizkurve')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byKey(const Key('editCurve'))), findsOneWidget);
    expect(find.byKey(const Key('openLiveView')), findsNothing); // Live is a tab now
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
