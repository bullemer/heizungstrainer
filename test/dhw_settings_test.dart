import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/dhw_settings_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';

/// The user's circulation pump times as read from PNU 3310+ (= Danfoss portal).
WeekSchedule realCirculation() => WeekSchedule.fromRaw([
      [600, 1600, 1600, 2200, 2400, 2400],
      for (var d = 1; d <= 4; d++) [200, 1600, 1600, 2200, 2400, 2400],
      [600, 900, 1200, 2300, 2400, 2400],
      [800, 1200, 1200, 2200, 2400, 2400],
    ]);

class _DhwProvider extends ECLProvider {
  _DhwProvider() : super(logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false), autoLoadDatabase: false);
  @override
  bool get supportsDhwSettings => true;
}

void main() {
  test('schedule areas: heating 3110, hot water 3210, circulation 3310 (register = PNU − 1)', () {
    expect(WeekSchedule.address(0, 0, stop: false, basePnu: WeekSchedule.circulationBasePnu), 3309);
    expect(WeekSchedule.address(1, 1, stop: true, basePnu: WeekSchedule.dhwBasePnu), 3222);
    expect(realCirculation().describeDay(0), '06:00–16:00, 16:00–22:00');
    expect(realCirculation().describeDay(6), '08:00–12:00, 12:00–22:00');
  });

  test('hot-water writes are refused without a verified controller', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final provider = ECLProvider(
      logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
      autoLoadDatabase: false,
    )..setConnectedForTesting(ip: '192.168.0.2');
    expect(() => provider.writeParameter(ECLRegisters.dhwComfortSetpoint, 50), throwsA(isA<ModbusCommunicationException>()));
    expect(() => provider.writeCirculationDay(0, List.filled(3, SchedulePeriod.unused)),
        throwsA(isA<ModbusCommunicationException>()));
    provider.dispose();
  });

  testWidgets('screen shows the real hot-water settings', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = _DhwProvider()
      ..setReadingForTesting(ECLRegisters.dhwComfortSetpoint, 55)
      ..setReadingForTesting(ECLRegisters.dhwSavingSetpoint, 50)
      ..setReadingForTesting(ECLRegisters.dhwMode, 2)
      ..setReadingForTesting(ECLRegisters.antiBacteriaTemp, 9)
      ..setReadingForTesting(ECLRegisters.antiBacteriaDays, 0)
      ..setReadingForTesting(ECLRegisters.antiBacteriaDuration, 120)
      ..setDhwSchedulesForTesting(circulation: realCirculation());
    await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
      value: provider,
      child: const MaterialApp(home: DhwSettingsScreen()),
    ));
    await tester.pump();
    expect(find.text('55 °C'), findsOneWidget);
    expect(find.text('50 °C'), findsOneWidget);
    expect(find.text('aus'), findsOneWidget); // legionella off
    expect(find.text('06:00–16:00, 16:00–22:00'), findsOneWidget);
    expect(find.text('02:00–16:00, 16:00–22:00'), findsNWidgets(4));
    final mode = tester.widget<SegmentedButton<int>>(find.byKey(const Key('dhwMode')));
    expect(mode.selected, {2});

    // editing a circulation day asks first
    await tester.tap(find.byKey(const Key('circ_0')));
    await tester.pumpAndSettle();
    expect(find.text('Zirkulation Montag'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
