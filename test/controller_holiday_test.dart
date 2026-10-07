import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/models/controller_holiday.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/holiday_service.dart';

/// Provider whose controller keeps holiday schedules in memory.
class _HolidayController extends ECLProvider {
  _HolidayController()
      : super(logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false), autoLoadDatabase: false);

  final Map<int, ControllerHolidayEntry> slots = {
    for (var s = 5; s <= 8; s++) s: ControllerHolidayEntry(slot: s, mode: ControllerHolidayMode.off, start: DateTime(2015), end: DateTime(2015)),
  };
  int cleared = 0;

  @override
  bool get supportsControllerHoliday => true;
  @override
  bool get isConnected => true;
  @override
  Future<List<ControllerHolidayEntry>> readControllerHolidays() async => slots.values.toList();
  @override
  Future<ControllerHolidayEntry> writeControllerHoliday({
    required DateTime start,
    required DateTime end,
    required ControllerHolidayMode mode,
  }) async {
    final free = slots.values.firstWhere((e) => !e.isSet);
    return slots[free.slot] = ControllerHolidayEntry(slot: free.slot, mode: mode, start: start, end: end);
  }

  @override
  Future<void> clearControllerHoliday(int slot) async {
    cleared++;
    slots[slot] = ControllerHolidayEntry(slot: slot, mode: ControllerHolidayMode.off, start: DateTime(2015), end: DateTime(2015));
  }
}

HolidayPlan week(DateTime now) => HolidayPlan(
      id: 'p1',
      title: '1 Woche Urlaub',
      startDateTime: now,
      endDateTime: now.add(const Duration(days: 7)),
      preheatHours: 24,
      createdAt: now,
    );

void main() {
  test('register layout: P1 at 10699, P5 at 10727', () {
    expect(ControllerHolidayEntry.address(1, 0), 10699);
    expect(ControllerHolidayEntry.address(5, 0), 10727);
    expect(ControllerHolidayEntry.address(12, 6), 10782);
  });

  test('decodes the real (unused) controller schedules', () {
    final e = ControllerHolidayEntry.fromRaw(1, [0, 1, 1, 2015, 1, 1, 2015]);
    expect(e.isSet, isFalse);
    expect(e.start, DateTime(2015));
    final set = ControllerHolidayEntry.fromRaw(5, [3, 10, 10, 2026, 17, 10, 2026]);
    expect(set.describe(), 'P5 Spar 10.10.2026 00:00 – 17.10.2026 00:00');
    expect(ControllerHolidayEntry.fromRaw(2, [3, 31, 2, 2026, 1, 3, 2026]).start, isNull); // invalid date
  });

  test('dates: start day 00:00, end at the midnight before the heat-up time (never later)', () {
    final d = ControllerHolidayLayout.datesFor(start: DateTime(2026, 10, 10, 15), heatUpFrom: DateTime(2026, 10, 16, 18))!;
    expect(d.start, DateTime(2026, 10, 10));
    expect(d.end, DateTime(2026, 10, 16));
    final d2 = ControllerHolidayLayout.datesFor(start: DateTime(2026, 10, 10), heatUpFrom: DateTime(2026, 10, 16, 6))!;
    expect(d2.end, DateTime(2026, 10, 16));
    expect(ControllerHolidayLayout.datesFor(start: DateTime(2026, 10, 10, 9), heatUpFrom: DateTime(2026, 10, 10, 20)), isNull);
  });

  test('A247 heating holidays are P3–P6 (verified live); others not enabled', () {
    expect(ControllerHolidayLayout.heatingSlotsFor('A247.1 v4.00'), [3, 4, 5, 6]);
    expect(ControllerHolidayLayout.heatingSlotsFor('A266.1 v1.08'), isNull);
    expect(ControllerHolidayLayout.heatingSlotsFor(null), isNull);
  });

  group('holiday in the controller', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('stores the absence in a controller schedule (saving mode) and closes it when over', () async {
      final provider = _HolidayController()
        ..setReadingForTesting(ECLRegisters.roomTargetTemp, 21)
        ..setReadingForTesting(ECLRegisters.savingRoomTemp, 18);
      final service = HolidayService(inMemoryStorage: {});
      final now = DateTime(2026, 10, 10, 15);

      final plan = await service.activatePlan(plan: week(now), provider: provider, now: now);
      expect(plan.runsInController, isTrue);
      expect(plan.controllerSlot, 5);
      expect(plan.targetRoomTemp, 18);
      final e = provider.slots[5]!;
      expect(e.mode, ControllerHolidayMode.saving);
      expect(e.start, DateTime(2026, 10, 10));
      expect(e.end, DateTime(2026, 10, 16)); // heat-up from 16.10. 15:00 → resume at 16.10. 00:00

      // during the absence nothing to do
      expect(await service.runDueActions(provider: provider, now: DateTime(2026, 10, 12)), isNull);
      // after the controller ended it: plan closed, schedule tidied up
      final done = await service.runDueActions(provider: provider, now: DateTime(2026, 10, 16, 1));
      expect(done!.isCompleted, isTrue);
      expect(provider.slots[5]!.isSet, isFalse);
    });

    test('refuses when the saving setpoint is not below comfort (would heat warmer)', () async {
      final provider = _HolidayController()
        ..setReadingForTesting(ECLRegisters.roomTargetTemp, 21)
        ..setReadingForTesting(ECLRegisters.savingRoomTemp, 25);
      final service = HolidayService(inMemoryStorage: {});
      expect(
        () => service.activatePlan(plan: week(DateTime(2026, 10, 10, 15)), provider: provider, now: DateTime(2026, 10, 10, 15)),
        throwsA(isA<HolidayModeException>().having((e) => e.message, 'message', contains('25.0 °C'))),
      );
      expect(provider.slots.values.any((e) => e.isSet), isFalse);
    });

    test('schedule deleted in the controller → error alert, plan closed', () async {
      final provider = _HolidayController()
        ..setReadingForTesting(ECLRegisters.roomTargetTemp, 21)
        ..setReadingForTesting(ECLRegisters.savingRoomTemp, 18);
      final service = HolidayService(inMemoryStorage: {});
      final now = DateTime(2026, 10, 10, 15);
      await service.activatePlan(plan: week(now), provider: provider, now: now);
      provider.slots[5] = ControllerHolidayEntry(slot: 5, mode: ControllerHolidayMode.off, start: DateTime(2015), end: DateTime(2015));

      final closed = await service.runDueActions(provider: provider, now: DateTime(2026, 10, 11));
      expect(closed!.isCompleted, isTrue);
      expect(provider.alerts.alerts.single.title, 'Urlaub fehlt im Regler');
    });

    test('cancelling removes the schedule from the controller', () async {
      final provider = _HolidayController()
        ..setReadingForTesting(ECLRegisters.roomTargetTemp, 21)
        ..setReadingForTesting(ECLRegisters.savingRoomTemp, 18);
      final service = HolidayService(inMemoryStorage: {});
      final now = DateTime(2026, 10, 10, 15);
      final plan = await service.activatePlan(plan: week(now), provider: provider, now: now);
      await service.cancelOrFinishPlan(plan: plan, provider: provider);
      expect(provider.cleared, 1);
      expect(provider.slots[5]!.isSet, isFalse);
    });
  });
}
