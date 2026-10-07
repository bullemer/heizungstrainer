import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/controller_settings_watch.dart';
import 'package:heizungstrainer/widgets/controller_schedule_card.dart';

/// Raw registers as read from the user's ECL 310 on 2026-10-08:
/// Monday all 2400 (no comfort period), Tue–Sun 0–2400.
WeekSchedule realSchedule() => WeekSchedule.fromRaw([
      [2400, 2400, 2400, 2400, 2400, 2400],
      for (var d = 1; d < 7; d++) [0, 2400, 2400, 2400, 2400, 2400],
    ]);

void main() {
  test('register addresses follow PNU 3110 + 10·day + 2·period − 1', () {
    expect(WeekSchedule.address(0, 0, stop: false), 3109); // Mon P1 start
    expect(WeekSchedule.address(1, 0, stop: true), 3120); // Tue P1 stop
    expect(WeekSchedule.address(6, 2, stop: true), 3174); // Sun P3 stop
  });

  test('decodes the real controller schedule', () {
    final s = realSchedule();
    expect(s.hasComfort(0), isFalse);
    expect(s.describeDay(0), 'keine Komfortzeit');
    expect(s.describeDay(1), '00:00–24:00');
    expect(s.mostCommonDay, [SchedulePeriod.allDay, SchedulePeriod.unused, SchedulePeriod.unused]);
    expect(WeekSchedule.decode(s.encode())!.sameDay(s, 0), isTrue);
    expect(eclModeLabel(1), 'Zeitprogramm');
  });

  test('watch remembers who wrote the schedule', () async {
    final watch = ControllerSettingsWatch(inMemoryStorage: {});
    await watch.saveSchedule('x', realSchedule(), byApp: true);
    final known = await watch.knownSchedule('x');
    expect(known.byApp, isTrue);
    expect(known.schedule!.hasComfort(0), isFalse);
  });

  testWidgets('card shows Monday and the saving setpoint as problems with fixes', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final provider = ECLProvider(
      logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
      autoLoadDatabase: false,
    );
    provider.setReadingForTesting(ECLRegisters.roomTargetTemp, 21);
    provider.setReadingForTesting(ECLRegisters.savingRoomTemp, 25);
    provider.setReadingForTesting(ECLRegisters.circuitMode, 1);
    provider.setControllerScheduleForTesting(realSchedule());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ControllerScheduleCard(provider: provider))),
    ));
    expect(find.text('Zeitprogramm'), findsOneWidget);
    expect(find.text('keine Komfortzeit → ganztags Spar 25 °C'), findsOneWidget);
    expect(find.text('Komfort 00:00–24:00'), findsNWidgets(6));
    expect(find.byKey(const Key('fixSaving')), findsOneWidget);
    expect(find.byKey(const Key('fixEmptyDays')), findsOneWidget);
    expect(find.textContaining('Montag hat keine Komfortzeit'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fixEmptyDays')));
    await tester.pumpAndSettle();
    expect(find.text('An Regler senden'), findsOneWidget); // asks before writing
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
