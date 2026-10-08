import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/dhw_settings_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/circulation_profiles.dart';

/// The user's circulation times (PNU 3310+, 2026-10-08).
final current = WeekSchedule.fromRaw([
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
  test('current times ≈ 17.7 h/day; profiles run clearly less', () {
    expect(circulationHoursPerDay(current), closeTo(17.71, 0.01));
    final hours = {for (final p in CirculationProfile.profiles) p.id: circulationHoursPerDay(p.schedule)};
    expect(hours['working'], closeTo(9.5, 0.01)); // (5×7.5 h + 2×14.5 h) / 7
    expect(hours['home'], closeTo(15.71, 0.01)); // (5×16 + 2×15) / 7
    expect(hours['minimal'], closeTo(5.14, 0.01)); // (5×5 + 2×5.5) / 7
  });

  test('profiles are valid Danfoss schedules (chronological, 30-min steps, ≤ 3 periods)', () {
    for (final p in CirculationProfile.profiles) {
      for (var d = 0; d < 7; d++) {
        final periods = p.periodsFor(d);
        expect(periods, hasLength(3));
        final active = periods.where((x) => x.isActive).toList();
        for (var i = 0; i < active.length; i++) {
          expect(active[i].start % 100 % 30, 0);
          expect(active[i].stop % 100 % 30, 0);
          if (i > 0) expect(active[i].start, greaterThanOrEqualTo(active[i - 1].stop));
        }
      }
    }
  });

  test('saving estimate: 100–200 W per running hour', () {
    final s = circulationSavingKwh(7);
    expect(s.low, closeTo(255.5, 0.1));
    expect(s.high, closeTo(511, 0.1));
    expect(circulationSavingKwh(-2).high, 0);
  });

  testWidgets('button opens the profiles with savings; nothing is written without confirmation', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = _DhwProvider()..setDhwSchedulesForTesting(circulation: current);
    await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
      value: provider,
      child: const MaterialApp(home: DhwSettingsScreen()),
    ));
    await tester.pump();
    expect(find.text('Optimale Zeiten (jetzt 18 Std./Tag)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('circOptimal')));
    await tester.pumpAndSettle();
    expect(find.text('Berufstätig'), findsOneWidget);
    expect(find.textContaining('9.5 Std./Tag statt 17.7'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile_working')));
    await tester.pumpAndSettle();
    expect(find.textContaining('„Berufstätig“ übernehmen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(provider.circulationSchedule!.sameDay(current, 1), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
