import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/holiday_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/holiday_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HolidayPlan Model Tests', () {
    final start = DateTime(2026, 9, 10, 10, 0);
    final end = DateTime(2026, 9, 12, 10, 0); // 48 hours later
    final created = DateTime(2026, 9, 8, 12, 0);

    final testPlan = HolidayPlan(
      id: 'plan_test_1',
      title: 'Wochenende Paris',
      startDateTime: start,
      endDateTime: end,
      setbackShift: -4.0,
      targetRoomTemp: 16.0,
      normalShift: 1.0,
      normalRoomTemp: 21.5,
      preheatHours: 4.0,
      frostProtectionMinTemp: 14.0,
      isActive: true,
      isCompleted: false,
      estimatedSavingsKwh: 36.0,
      estimatedSavingsEuro: 4.68,
      createdAt: created,
    );

    test('serializes and deserializes accurately', () {
      final json = testPlan.toJson();
      final restored = HolidayPlan.fromJson(json);

      expect(restored.id, 'plan_test_1');
      expect(restored.title, 'Wochenende Paris');
      expect(restored.startDateTime, start);
      expect(restored.endDateTime, end);
      expect(restored.setbackShift, -4.0);
      expect(restored.targetRoomTemp, 16.0);
      expect(restored.normalShift, 1.0);
      expect(restored.normalRoomTemp, 21.5);
      expect(restored.preheatHours, 4.0);
      expect(restored.frostProtectionMinTemp, 14.0);
      expect(restored.isActive, true);
      expect(restored.isCompleted, false);
      expect(restored.estimatedSavingsKwh, 36.0);
      expect(restored.estimatedSavingsEuro, 4.68);
      expect(restored.createdAt, created);
    });

    test('calculates duration correctly', () {
      expect(testPlan.duration, const Duration(hours: 48));
    });

    test('calculates preheatStartTime correctly', () {
      // end is 2026-09-12 10:00, preheat is 4h -> 2026-09-12 06:00
      expect(testPlan.preheatStartTime, DateTime(2026, 9, 12, 6, 0));
    });

    test('evaluates isInAbsencePeriod and isPreheatingActive correctly', () {
      // Before start
      final before = DateTime(2026, 9, 9, 12, 0);
      expect(testPlan.isInAbsencePeriod(before), false);
      expect(testPlan.isPreheatingActive(before), false);

      // In absence but before preheat (e.g. 2026-09-11 12:00)
      final midAbsence = DateTime(2026, 9, 11, 12, 0);
      expect(testPlan.isInAbsencePeriod(midAbsence), true);
      expect(testPlan.isPreheatingActive(midAbsence), false);

      // In preheat window (e.g. 2026-09-12 08:00)
      final duringPreheat = DateTime(2026, 9, 12, 8, 0);
      expect(testPlan.isInAbsencePeriod(duringPreheat), true);
      expect(testPlan.isPreheatingActive(duringPreheat), true);

      // After end
      final after = DateTime(2026, 9, 13, 10, 0);
      expect(testPlan.isInAbsencePeriod(after), false);
      expect(testPlan.isPreheatingActive(after), false);

      // When completed or inactive, neither is active
      final completedPlan = testPlan.copyWith(isCompleted: true);
      expect(completedPlan.isInAbsencePeriod(duringPreheat), false);
      expect(completedPlan.isPreheatingActive(duringPreheat), false);
    });

    test('encodes and decodes lists of plans', () {
      final list = [
        testPlan,
        testPlan.copyWith(id: 'plan_test_2', title: 'Skiurlaub'),
      ];

      final encoded = HolidayPlan.encodeList(list);
      final decoded = HolidayPlan.decodeList(encoded);

      expect(decoded.length, 2);
      expect(decoded[0].id, 'plan_test_1');
      expect(decoded[1].id, 'plan_test_2');
      expect(decoded[1].title, 'Skiurlaub');
    });

    test('copyWith modifies only target fields', () {
      final modified = testPlan.copyWith(
        title: 'Neuer Titel',
        setbackShift: -5.0,
      );

      expect(modified.title, 'Neuer Titel');
      expect(modified.setbackShift, -5.0);
      expect(modified.id, testPlan.id);
      expect(modified.targetRoomTemp, testPlan.targetRoomTemp);
    });
  });

  group('HolidayService Logic & Storage Tests', () {
    test('calculateSavings returns sensible estimates and handles zero duration', () {
      final service = HolidayService(inMemoryStorage: {});

      final zero = service.calculateSavings(duration: Duration.zero);
      expect(zero['kwh'], 0.0);
      expect(zero['euro'], 0.0);

      final weekend = service.calculateSavings(duration: const Duration(hours: 60));
      expect(weekend['kwh']!, greaterThan(0.0));
      expect(weekend['euro']!, greaterThan(0.0));
      // 60h * 2.5 kW * (5 * 0.06 = 0.30) = 45.0 kWh
      expect(weekend['kwh'], 45.0);
      // 45.0 kWh * 0.13 €/kWh = 5.85 €
      expect(weekend['euro'], 5.85);
    });

    test('saves, retrieves, and deletes plans via in-memory storage', () async {
      final storage = <String, String>{};
      final service = HolidayService(inMemoryStorage: storage);

      expect(await service.getAllPlans(), isEmpty);
      expect(await service.getActivePlan(), isNull);

      final plan1 = HolidayPlan(
        id: 'p1',
        title: 'Plan Eins',
        startDateTime: DateTime(2026, 9, 10),
        endDateTime: DateTime(2026, 9, 12),
        createdAt: DateTime(2026, 9, 1),
        isActive: false,
        isCompleted: true,
      );

      final plan2 = HolidayPlan(
        id: 'p2',
        title: 'Plan Zwei Aktiv',
        startDateTime: DateTime(2026, 9, 15),
        endDateTime: DateTime(2026, 9, 18),
        createdAt: DateTime(2026, 9, 2),
        isActive: true,
        isCompleted: false,
      );

      await service.savePlan(plan1);
      await service.savePlan(plan2);

      final all = await service.getAllPlans();
      expect(all.length, 2);
      // Newest created should be first
      expect(all.first.id, 'p2');

      final active = await service.getActivePlan();
      expect(active, isNotNull);
      expect(active!.id, 'p2');

      await service.deletePlan('p1');
      final remaining = await service.getAllPlans();
      expect(remaining.length, 1);
      expect(remaining.first.id, 'p2');
    });

    test('activatePlan and cancelOrFinishPlan update plan state and log actions', () async {
      final storage = <String, String>{};
      final service = HolidayService(inMemoryStorage: storage);
      final logService = ActivityLogService(
        enablePersistence: false,
        enableRemoteDispatch: false,
      );
      final provider = ECLProvider(logService: logService);

      final initialPlan = HolidayPlan(
        id: 'p_dyn',
        title: 'Herbstferien',
        startDateTime: DateTime(2026, 10, 1),
        endDateTime: DateTime(2026, 10, 10),
        setbackShift: -3.0,
        createdAt: DateTime(2026, 9, 8),
      );

      final activated = await service.activatePlan(
        plan: initialPlan,
        provider: provider,
      );
      expect(activated.isActive, true);
      expect(activated.isCompleted, false);

      final activeInDb = await service.getActivePlan();
      expect(activeInDb?.id, 'p_dyn');

      expect(
        logService.recentEntries.any((l) => l.action == 'HOLIDAY_MODE_ACTIVATED'),
        true,
      );

      final cancelled = await service.cancelOrFinishPlan(
        plan: activated,
        provider: provider,
      );
      expect(cancelled.isActive, false);
      expect(cancelled.isCompleted, true);

      final activeAfterCancel = await service.getActivePlan();
      expect(activeAfterCancel, isNull);

      expect(
        logService.recentEntries.any((l) => l.action == 'HOLIDAY_MODE_DEACTIVATED'),
        true,
      );
    });
  });

  group('HolidayScreen Widget Tests', () {
    testWidgets('renders header, quick presets, and zero-cloud banner', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = HolidayService(inMemoryStorage: {});
      final logService = ActivityLogService(
        enablePersistence: false,
        enableRemoteDispatch: false,
      );
      final provider = ECLProvider(logService: logService);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: HolidayScreen(holidayService: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header title
      expect(find.textContaining('Urlaub & Abwesenheit'), findsOneWidget);

      // Presets
      expect(find.textContaining('Wochenend-Trip'), findsOneWidget);
      expect(find.textContaining('1 Woche Urlaub'), findsOneWidget);
      expect(find.textContaining('2 Wochen Reise'), findsOneWidget);
      expect(find.textContaining('Kurztrip'), findsOneWidget);

      // Status card when inactive
      expect(find.text('Normalbetrieb aktiv'), findsOneWidget);
      expect(find.text('Eigene Abwesenheit planen'), findsOneWidget);

      // Local autonomy info
      expect(find.text('100% Local-First & Hardware-Autonomie'), findsOneWidget);
    });

    testWidgets('displays active plan card when plan is running', (tester) async {
      final now = DateTime.now();
      final storage = <String, String>{};
      final service = HolidayService(inMemoryStorage: storage);
      final logService = ActivityLogService(
        enablePersistence: false,
        enableRemoteDispatch: false,
      );
      final provider = ECLProvider(logService: logService);

      final activePlan = HolidayPlan(
        id: 'active_123',
        title: 'Wochenende im Harz',
        startDateTime: now.subtract(const Duration(hours: 5)),
        endDateTime: now.add(const Duration(hours: 43)),
        setbackShift: -3.0,
        preheatHours: 4.0,
        estimatedSavingsKwh: 36.0,
        estimatedSavingsEuro: 4.68,
        createdAt: now.subtract(const Duration(hours: 5)),
        isActive: true,
        isCompleted: false,
      );
      await service.savePlan(activePlan);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: HolidayScreen(holidayService: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check active card contents
      expect(find.text('Wochenende im Harz'), findsOneWidget);
      expect(find.text('Sparbetrieb aktiv'), findsOneWidget);
      expect(find.text('Vorzeitig beenden & Heizung hochfahren'), findsOneWidget);
      expect(find.textContaining('4.68 €'), findsWidgets);
    });

    testWidgets('activating a preset via button updates UI', (tester) async {
      final storage = <String, String>{};
      final service = HolidayService(inMemoryStorage: storage);
      final logService = ActivityLogService(
        enablePersistence: false,
        enableRemoteDispatch: false,
      );
      final provider = ECLProvider(logService: logService);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: HolidayScreen(holidayService: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Normalbetrieb aktiv'), findsOneWidget);

      // Tap on 'Wochenend-Trip' preset card
      await tester.tap(find.textContaining('Wochenend-Trip'));
      await tester.pumpAndSettle();

      // Should now show SnackBar and active plan
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Sparbetrieb aktiv'), findsOneWidget);
      expect(find.textContaining('Wochenend-Trip'), findsWidgets);
    });
  });
}
