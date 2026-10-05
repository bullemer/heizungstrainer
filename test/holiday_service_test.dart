import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/holiday_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/services/holiday_service.dart';
import 'package:heizungstrainer/services/license_service.dart';
import 'package:heizungstrainer/widgets/holiday_end_flow.dart';

/// Provider connected to the simulated controller with Pro (write) access.
Future<ECLProvider> connectedSimulation(ActivityLogService logService) async {
  final provider = ECLProvider(
    logService: logService,
    licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
    autoLoadDatabase: false,
  );
  await provider.startSimulation();
  return provider;
}

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
    test('absence savings: ~6 %/°C on the seasonal daily consumption, preheat excluded', () {
      // January: 3100 kWh/month (31 days) = 100 kWh/day
      double daily(DateTime d) => d.month == 1 ? 100 : 10;
      final start = DateTime(2027, 1, 10, 0);
      final s = AbsenceSavings.estimate(
        start: start,
        preheatStart: start.add(const Duration(days: 2)), // 48 h setback
        roomReductionKelvin: 4,
        dailyHeatingKwh: daily,
        pricePerKwh: 0.125,
      );
      expect(s.percent, 24); // 4 °C × 6 %
      expect(s.kwh, closeTo(2 * 100 * 0.24, 1e-6)); // 48 kWh
      expect(s.euro, closeTo(6.0, 1e-6));

      // without consumption data only the percentage is known
      final pctOnly = AbsenceSavings.estimate(
        start: start, preheatStart: start.add(const Duration(days: 2)), roomReductionKelvin: 4);
      expect(pctOnly.kwh, isNull);
      expect(pctOnly.euro, isNull);
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
      final provider = await connectedSimulation(logService);
      await provider.writeParameter(ECLRegisters.heatingCurveShift, 2.0);

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
        now: DateTime(2026, 10, 1, 12),
      );
      expect(activated.isActive, true);
      expect(activated.isCompleted, false);
      expect(activated.setbackApplied, true);
      expect(activated.normalShift, 2.0); // real baseline, not a default
      expect(provider.getReading(ECLRegisters.heatingCurveShift)!.displayValue, -3.0);

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
      expect(provider.getReading(ECLRegisters.heatingCurveShift)!.displayValue, 2.0);

      final activeAfterCancel = await service.getActivePlan();
      expect(activeAfterCancel, isNull);

      expect(
        logService.recentEntries.any((l) => l.action == 'HOLIDAY_MODE_DEACTIVATED'),
        true,
      );
    });
  });

  group('HolidayService safety', () {
    HolidayPlan plan({required DateTime start, required DateTime end}) => HolidayPlan(
          id: 'p_safe',
          title: 'Test',
          startDateTime: start,
          endDateTime: end,
          setbackShift: -3.0,
          preheatHours: 4.0,
          createdAt: start,
        );
    ActivityLogService logs() =>
        ActivityLogService(enablePersistence: false, enableRemoteDispatch: false);

    test('activation without connection fails and saves nothing', () async {
      final service = HolidayService(inMemoryStorage: {});
      final provider = ECLProvider(logService: logs(), autoLoadDatabase: false);
      final now = DateTime(2026, 10, 1, 12);

      await expectLater(
        service.activatePlan(
          plan: plan(start: now, end: now.add(const Duration(days: 2))),
          provider: provider,
          now: now,
        ),
        throwsA(isA<HolidayModeException>()),
      );
      expect(await service.getActivePlan(), isNull);
    });

    test('failed write (free tier) does not leave an active plan', () async {
      final service = HolidayService(inMemoryStorage: {});
      final provider = ECLProvider(
        logService: logs(),
        licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.free),
        autoLoadDatabase: false,
      );
      await provider.startSimulation();
      final now = DateTime(2026, 10, 1, 12);

      await expectLater(
        service.activatePlan(
          plan: plan(start: now, end: now.add(const Duration(days: 2))),
          provider: provider,
          now: now,
        ),
        throwsA(isA<HolidayModeException>()),
      );
      expect(await service.getActivePlan(), isNull);
    });

    test('future plan is armed, then applied and restored by runDueActions', () async {
      final service = HolidayService(inMemoryStorage: {});
      final provider = await connectedSimulation(logs());
      await provider.writeParameter(ECLRegisters.heatingCurveShift, 1.0);
      final start = DateTime(2026, 10, 2, 8);
      final end = DateTime(2026, 10, 4, 18);

      final armed = await service.activatePlan(
        plan: plan(start: start, end: end),
        provider: provider,
        now: DateTime(2026, 10, 1, 12),
      );
      expect(armed.setbackApplied, false);
      expect(provider.getReading(ECLRegisters.heatingCurveShift)!.displayValue, 1.0);

      // Before start: nothing to do.
      expect(await service.runDueActions(provider: provider, now: DateTime(2026, 10, 2, 7)), isNull);

      final lowered = await service.runDueActions(provider: provider, now: DateTime(2026, 10, 2, 9));
      expect(lowered!.setbackApplied, true);
      expect(lowered.normalShift, 1.0);
      expect(provider.getReading(ECLRegisters.heatingCurveShift)!.displayValue, -3.0);

      // Preheat starts 4 h before return (14:00).
      final restored = await service.runDueActions(provider: provider, now: DateTime(2026, 10, 4, 14, 1));
      expect(restored!.isCompleted, true);
      expect(provider.getReading(ECLRegisters.heatingCurveShift)!.displayValue, 1.0);
      expect(await service.getActivePlan(), isNull);
    });

    test('restore fails while disconnected and the plan stays active', () async {
      final service = HolidayService(inMemoryStorage: {});
      final provider = await connectedSimulation(logs());
      await provider.writeParameter(ECLRegisters.heatingCurveShift, 0.0);
      final now = DateTime(2026, 10, 1, 12);
      final active = await service.activatePlan(
        plan: plan(start: now, end: now.add(const Duration(days: 2))),
        provider: provider,
        now: now,
      );

      provider.disconnect();
      await expectLater(
        service.cancelOrFinishPlan(plan: active, provider: provider),
        throwsA(isA<HolidayModeException>()),
      );
      expect((await service.getActivePlan())?.id, active.id);

      // Explicitly closing without restore is allowed.
      final closed = await service.cancelOrFinishPlan(
        plan: active,
        provider: provider,
        restore: false,
      );
      expect(closed.isCompleted, true);
    });

    test('unreadable storage is not overwritten by savePlan', () async {
      final storage = <String, String>{'ecl_holiday_plans': 'not json'};
      final service = HolidayService(inMemoryStorage: storage);
      final now = DateTime(2026, 10, 1, 12);

      await expectLater(
        service.savePlan(plan(start: now, end: now.add(const Duration(days: 1)))),
        throwsA(anything),
      );
      expect(storage['ecl_holiday_plans'], 'not json');
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
        setbackApplied: true,
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
      final provider = (await tester.runAsync(() => connectedSimulation(logService)))!;
      addTearDown(provider.disconnect);

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

      // Tap on 'Wochenend-Trip' preset card. The write mixes a settle delay
      // (fake clock) with real SQLite I/O, so advance both until it's done.
      await tester.tap(find.textContaining('Wochenend-Trip'));
      await tester.pumpAndSettle();
      // presets ask before writing to the heating
      expect(find.text('Wochenend-Trip starten?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmPreset')));
      for (var i = 0; i < 20 && find.byType(SnackBar).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Should now show SnackBar and active plan
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Sparbetrieb aktiv'), findsOneWidget);
      expect(find.textContaining('Wochenend-Trip'), findsWidgets);
    });
  });

  group('Holiday mode via comfort room setpoint (controller without curve shift)', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    Future<(ECLProvider, _RoomOnlyController)> roomOnlyProvider() async {
      final fake = _RoomOnlyController(room: 22);
      final provider = ECLProvider(
        logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
        licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
        autoLoadDatabase: false,
      );
      await provider.setSelectedController('nibe_modbus');
      provider.useControllerForTesting(fake);
      provider.setConnectedForTesting(ip: '192.168.178.60');
      await provider.setBetaWritesEnabled(true);
      await provider.refreshReadings();
      return (provider, fake);
    }

    test('lowers the room setpoint by the chosen °C and restores it', () async {
      final (provider, fake) = await roomOnlyProvider();
      expect(provider.holidayControlMode, 'room');
      final service = HolidayService(inMemoryStorage: {});
      final now = DateTime(2026, 10, 6, 12);

      final active = await service.activatePlan(
        plan: HolidayPlan(
          id: 'p_room', title: 'Urlaub', startDateTime: now,
          endDateTime: now.add(const Duration(days: 7)), roomSetbackKelvin: 4, createdAt: now),
        provider: provider,
        now: now,
      );
      expect(active.controlMode, 'room');
      expect(active.normalRoomTemp, 22);
      expect(active.targetRoomTemp, 18);
      expect(fake.room, 18);

      await service.cancelOrFinishPlan(plan: active, provider: provider);
      expect(fake.room, 22);
    });

    test('never goes below 15 °C', () async {
      final (provider, fake) = await roomOnlyProvider();
      final service = HolidayService(inMemoryStorage: {});
      final now = DateTime(2026, 10, 6, 12);
      final active = await service.activatePlan(
        plan: HolidayPlan(
          id: 'p_low', title: 'Lang', startDateTime: now,
          endDateTime: now.add(const Duration(days: 14)), roomSetbackKelvin: 10, createdAt: now),
        provider: provider,
        now: now,
      );
      expect(active.targetRoomTemp, 15);
      expect(fake.room, 15);
    });
  });

  testWidgets('start page card shows the active plan and ends it with confirmation', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final (provider, fake) = (await tester.runAsync(() async {
      final fake = _RoomOnlyController(room: 22);
      final p = ECLProvider(
        logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
        licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
        autoLoadDatabase: false,
      );
      await p.setSelectedController('nibe_modbus');
      p.useControllerForTesting(fake);
      p.setConnectedForTesting(ip: '192.168.178.60');
      await p.setBetaWritesEnabled(true);
      await p.refreshReadings();
      return (p, fake);
    }))!;
    final service = HolidayService(inMemoryStorage: {});
    final now = DateTime.now();
    await tester.runAsync(() => service.activatePlan(
          plan: HolidayPlan(
              id: 'p_home', title: '1 Woche Urlaub', startDateTime: now,
              endDateTime: now.add(const Duration(days: 7)), roomSetbackKelvin: 4, createdAt: now),
          provider: provider,
          now: now,
        ));
    expect(fake.room, 18);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ActiveHolidayCard(provider: provider, service: service))));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('Urlaubsmodus aktiv: 1 Woche Urlaub'), findsOneWidget);
    expect(find.textContaining('Raum-Sollwert auf 18.0 °C (normal 22.0 °C)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('endHolidayFromHome')));
    await tester.pumpAndSettle();
    expect(find.textContaining('zurück auf 22.0 °C'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmEndHoliday')));
    for (var i = 0; i < 10 && find.byKey(const Key('activeHolidayCard')).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fake.room, 22);
    expect(find.byKey(const Key('activeHolidayCard')), findsNothing);
  });
}

/// Like the user's ECL 310: comfort room setpoint, but no curve shift.
class _RoomOnlyController implements HeatingController {
  _RoomOnlyController({required this.room});
  double room;

  @override
  String get id => 'nibe_modbus';
  @override
  String get brandName => 'Test';
  @override
  String get modelName => 'Room only';
  @override
  ConnectionProtocol get protocol => ConnectionProtocol.modbusTcp;
  @override
  HeatingCapabilities get capabilities => const HeatingCapabilities(supportsHeatingCurveShift: false);
  @override
  bool get isConnected => true;
  @override
  Stream<ControllerTelemetry> get telemetryStream => const Stream.empty();
  @override
  Future<void> connect({required String host, int? port, Map<String, dynamic>? extraConfig}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<ControllerTelemetry> readTelemetry() async =>
      ControllerTelemetry(timestamp: DateTime.now(), flowTemp: 30, roomTarget: room);
  @override
  Future<void> setHeatingCurveShift(double shift) async => throw UnsupportedError('no shift');
  @override
  Future<void> setRoomTarget(double temperature) async => room = temperature;
}
