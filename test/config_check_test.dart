import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/controller_holiday.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/config_check_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/config_check.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';

/// The user's ECL 310 (A247.1), as read on 2026-10-08.
const curve = ControllerHeatingCurve(
    outdoorTemps: [-30, -15, -5, 0, 5, 15], flowTemps: [40, 36, 32, 29, 26, 22], slope: 0.5, minFlow: 22, maxFlow: 50);
WeekSchedule week({bool mondayEmpty = false}) => WeekSchedule([
      for (var d = 0; d < 7; d++)
        [d == 0 && mondayEmpty ? SchedulePeriod.unused : SchedulePeriod.allDay, SchedulePeriod.unused, SchedulePeriod.unused],
    ]);
final circulation = WeekSchedule.fromRaw([
  [600, 1600, 1600, 2200, 2400, 2400],
  for (var d = 1; d <= 4; d++) [200, 1600, 1600, 2200, 2400, 2400],
  [600, 900, 1200, 2300, 2400, 2400],
  [800, 1200, 1200, 2200, 2400, 2400],
]);

ConfigCheckInput input({double saving = 18, bool mondayEmpty = false, double dhw = 55, int abTemp = 9}) => ConfigCheckInput(
      comfort: 21,
      saving: saving,
      heatingMode: 1,
      schedule: week(mondayEmpty: mondayEmpty),
      curve: curve,
      reference: BuildingReference.floorAfter2010,
      summerCutoff: 13,
      maxFlow: 50,
      dhwMode: 2,
      dhwComfort: dhw,
      dhwSaving: 50,
      antiBacteriaTemp: abTemp,
      antiBacteriaDays: 0,
      circulation: circulation,
      clockOffset: Duration.zero,
    );

List<String> ids(ConfigCheckInput i) => runConfigCheck(i).map((f) => f.id).toList();

void main() {
  test('state before the fixes: saving 25 > comfort and an empty Monday are problems', () {
    final f = runConfigCheck(input(saving: 25, mondayEmpty: true));
    expect(f.first.severity, FindingSeverity.problem);
    expect(f.map((x) => x.id), containsAll(['saving_above_comfort', 'schedule_empty_days']));
    expect(f.firstWhere((x) => x.id == 'schedule_empty_days').severity, FindingSeverity.problem);
  });

  test('current state: only floor-heating max flow and circulation hints remain', () {
    expect(ids(input()), unorderedEquals(['max_flow_floor', 'circulation_night', 'circulation_long']));
    final night = runConfigCheck(input()).firstWhere((f) => f.id == 'circulation_night');
    expect(night.title, 'Zirkulation läuft nachts (Di, Mi, Do, Fr)');
  });

  test('curve within the EnergieSchweiz band → no curve finding; too high → estimate', () {
    expect(ids(input()).where((i) => i.startsWith('curve_')), isEmpty);
    final high = runConfigCheck(ConfigCheckInput(
      curve: const ControllerHeatingCurve(
          outdoorTemps: [-30, -15, -5, 0, 5, 15], flowTemps: [75, 60, 50, 45, 40, 28], slope: 1.0),
      reference: BuildingReference.floorAfter2010,
    )).firstWhere((f) => f.id == 'curve_high');
    expect(high.severity, FindingSeverity.warning);
    expect(high.detail, contains('% Heizenergie'));
  });

  test('hot water: below 50 °C without legionella protection warns; with it, not', () {
    expect(ids(input(dhw: 48)), contains('dhw_legionella'));
    expect(ids(ConfigCheckInput(dhwComfort: 48, antiBacteriaTemp: 60, antiBacteriaDays: 1)), isNot(contains('dhw_legionella')));
  });

  test('controller: clock off by 20 min, alarms, expired holiday', () {
    final f = ids(ConfigCheckInput(
      clockOffset: const Duration(minutes: 20),
      alarms: const {3},
      heatingHolidays: [ControllerHolidayEntry(slot: 4, mode: ControllerHolidayMode.saving, start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 8))],
      now: DateTime(2026, 10, 8),
    ));
    expect(f, containsAll(['clock', 'alarm_3', 'holiday_old_4']));
    expect(f.first, 'alarm_3'); // problems first
  });

  testWidgets('screen lists findings and hides "ist so gewollt"', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = _CheckProvider(input());
    await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
      value: provider,
      child: const MaterialApp(home: ConfigCheckScreen()),
    ));
    await tester.pump();
    expect(find.byKey(const Key('finding_max_flow_floor')), findsOneWidget);
    expect(find.text('Zirkulation läuft nachts (Di, Mi, Do, Fr)'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const Key('finding_max_flow_floor')), matching: find.text('Ist so gewollt')));
    await tester.pump();
    expect(find.byKey(const Key('finding_max_flow_floor')), findsNothing);
    expect(find.text('1 ausgeblendete Hinweise wieder anzeigen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}

class _CheckProvider extends ECLProvider {
  _CheckProvider(this.fixed)
      : super(logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false), autoLoadDatabase: false);
  final ConfigCheckInput fixed;
  final Set<String> hidden = {};
  @override
  List<ConfigFinding> get configFindings => runConfigCheck(fixed).where((f) => !hidden.contains(f.id)).toList();
  @override
  int get dismissedFindingsCount => hidden.length;
  @override
  Future<void> dismissFinding(String id) async {
    hidden.add(id);
    notifyListeners();
  }
}
