import 'package:heizungstrainer/utils/number_format.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/services/alert_center.dart';
import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/models/controller_holiday.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';

/// Thrown when holiday mode cannot change the controller (no connection, no
/// trustworthy baseline reading, or the write was not confirmed).
class HolidayModeException implements Exception {
  final String message;
  const HolidayModeException(this.message);

  @override
  String toString() => message;
}

/// Manages persistent storage and hardware execution of holiday & absence mode.
///
/// The phone is the scheduler: lowering at the start and restoring at the
/// preheat time happen in [runDueActions], which the app calls periodically
/// while it is running. If the controller is unreachable at that moment, the
/// step is caught up on the next run where it is reachable.
class HolidayService {
  static const String _storageKey = 'ecl_holiday_plans';

  /// Bumped on every save so open screens can reload (plans also change from
  /// the background scheduler, not only from the holiday screen).
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _inMemory;

  HolidayService({
    FlutterSecureStorage? storage,
    Map<String, String>? inMemoryStorage,
  })  : _storage = inMemoryStorage != null
            ? null
            : (storage ?? const FlutterSecureStorage()),
        _inMemory = inMemoryStorage;

  /// Reads all plans. Throws if storage can't be read, so a slow or failing
  /// keystore never looks like "no plans" to a writer (which would overwrite them).
  Future<List<HolidayPlan>> _readPlans() async {
    final String? raw;
    final inMem = _inMemory;
    if (inMem != null) {
      raw = inMem[_storageKey];
    } else {
      raw = await _storage!
          .read(key: _storageKey)
          .timeout(const Duration(seconds: 5));
    }
    if (raw == null || raw.isEmpty) return [];
    final list = HolidayPlan.decodeList(raw);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Retrieves all holiday plans from storage, sorted newest first.
  /// For display only: returns an empty list if storage can't be read.
  Future<List<HolidayPlan>> getAllPlans() async {
    try {
      return await _readPlans();
    } catch (e) {
      debugPrint('[HolidayService] Could not read plans: $e');
      return [];
    }
  }

  /// Returns currently active plan if one exists.
  Future<HolidayPlan?> getActivePlan() async {
    final all = await getAllPlans();
    for (final plan in all) {
      if (plan.isActive && !plan.isCompleted) {
        return plan;
      }
    }
    return null;
  }

  /// Saves or updates a plan in storage.
  Future<void> savePlan(HolidayPlan plan) async {
    final existing = await _readPlans();
    final updated = [plan, ...existing.where((p) => p.id != plan.id)];
    await _write(HolidayPlan.encodeList(updated));
  }

  /// Deletes a plan by ID.
  Future<void> deletePlan(String id) async {
    final existing = await _readPlans();
    final updated = existing.where((p) => p.id != id).toList();
    await _write(HolidayPlan.encodeList(updated));
  }

  Future<void> _write(String encoded) async {
    final inMem = _inMemory;
    if (inMem != null) {
      inMem[_storageKey] = encoded;
    } else {
      await _storage!.write(key: _storageKey, value: encoded);
    }
    changes.value++;
  }

  /// Activates a holiday plan. If it starts now, the setback is written to the
  /// controller right away and the plan is only saved if that write is
  /// confirmed. A plan with a future start is saved "armed" and applied later
  /// by [runDueActions].
  Future<HolidayPlan> activatePlan({
    required HolidayPlan plan,
    required ECLProvider provider,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    if (provider.supportsControllerHoliday) {
      return _activateInController(plan, provider, at);
    }
    final armed = plan.copyWith(
      isActive: true,
      isCompleted: false,
      setbackApplied: false,
    );

    if (at.isBefore(plan.startDateTime)) {
      await savePlan(armed);
      await provider.logService.logWrite(
        controllerId: provider.selectedControllerId,
        action: 'HOLIDAY_MODE_ARMED',
        message:
            'Abwesenheitsmodus "${plan.title}" geplant: Absenkung ab ${plan.startDateTime.toIso8601String()}.',
        details: {'planId': plan.id, 'setbackShift': plan.setbackShift},
      );
      return armed;
    }

    final applied = await _applySetback(armed, provider);
    await savePlan(applied);
    return applied;
  }

  /// Stores the absence in the controller's own holiday program (saving
  /// mode), so it runs and ends without the app; normal heating resumes at
  /// the midnight before the planned preheat start.
  Future<HolidayPlan> _activateInController(HolidayPlan plan, ECLProvider provider, DateTime at) async {
    final comfort = provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue;
    final saving = provider.getReading(ECLRegisters.savingRoomTemp)?.displayValue;
    if (comfort == null || saving == null) {
      throw const HolidayModeException('Komfort- und Spar-Sollwert des Reglers sind noch nicht gelesen – bitte kurz warten.');
    }
    if (saving >= comfort) {
      throw HolidayModeException(
        'Der Spar-Sollwert des Reglers (${saving.fixed(1)} °C) ist nicht niedriger als Komfort '
        '(${comfort.fixed(1)} °C) – im Urlaub würde der Regler nicht absenken. Bitte zuerst auf der '
        'Startseite unter „Zeitprogramm im Regler“ den Spar-Sollwert anpassen.',
      );
    }
    final start = plan.startDateTime.isBefore(at) ? at : plan.startDateTime;
    final dates = ControllerHolidayLayout.datesFor(start: start, heatUpFrom: plan.preheatStartTime);
    if (dates == null) {
      throw const HolidayModeException(
          'Der Regler kann Urlaub nur tageweise (00:00–00:00, mindestens ein Tag). Bitte einen längeren Zeitraum wählen.');
    }
    final ControllerHolidayEntry entry;
    try {
      entry = await provider.writeControllerHoliday(start: dates.start, end: dates.end, mode: ControllerHolidayMode.saving);
    } catch (e) {
      throw HolidayModeException('Urlaub konnte nicht im Regler gespeichert werden: ${userFacingError(e)}');
    }
    final stored = plan.copyWith(
      isActive: true,
      isCompleted: false,
      setbackApplied: true,
      controlMode: 'controller',
      controllerSlot: entry.slot,
      normalRoomTemp: comfort,
      targetRoomTemp: saving,
    );
    await savePlan(stored);
    await provider.logService.logWrite(
      controllerId: provider.selectedControllerId,
      action: 'HOLIDAY_MODE_IN_CONTROLLER',
      message: 'Abwesenheit "${plan.title}" im Regler gespeichert (${entry.describe()}): '
          'Spar ${saving.fixed(1)} °C statt Komfort ${comfort.fixed(1)} °C – läuft auch ohne App.',
      details: {'planId': plan.id, 'slot': entry.slot},
    );
    return stored;
  }

  /// Lowest comfort setpoint holiday mode sets in room-setpoint mode.
  static const double minHolidayRoomSetpoint = 15.0;

  /// Reads the current value as the baseline to restore later, then writes the
  /// setback – via the curve shift if the controller has one, else via the
  /// comfort room setpoint. Throws [HolidayModeException] instead of guessing.
  Future<HolidayPlan> _applySetback(HolidayPlan plan, ECLProvider provider) async {
    if (!provider.isConnected) {
      throw const HolidayModeException(
        'Keine Verbindung zum Regler – die Absenkung wurde nicht aktiviert.',
      );
    }
    final mode = provider.holidayControlMode;
    if (mode == null) {
      throw const HolidayModeException(
        'Der Regler stellt weder Parallelverschiebung noch Raum-Sollwert bereit – '
        'eine Absenkung ist nicht möglich.',
      );
    }
    if (mode == 'room') return _applyRoomSetback(plan, provider);
    final currentShift =
        provider.getReading(ECLRegisters.heatingCurveShift)?.displayValue;
    if (currentShift == null) {
      throw const HolidayModeException(
        'Die aktuelle Parallelverschiebung ist nicht bekannt – ohne sie könnte '
        'der Normalbetrieb später nicht korrekt wiederhergestellt werden.',
      );
    }
    final currentRoom =
        provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue;

    try {
      await provider.writeParameter(
        ECLRegisters.heatingCurveShift,
        plan.setbackShift,
      );
    } catch (e) {
      throw HolidayModeException('Absenkung fehlgeschlagen: ${userFacingError(e)}');
    }

    final applied = plan.copyWith(
      normalShift: currentShift,
      normalRoomTemp: currentRoom ?? plan.normalRoomTemp,
      setbackApplied: true,
      controlMode: 'shift',
    );
    await provider.logService.logWrite(
      controllerId: provider.selectedControllerId,
      action: 'HOLIDAY_MODE_ACTIVATED',
      message:
          'Abwesenheitsmodus "${plan.title}" aktiv: Parallelverschiebung $currentShift → ${plan.setbackShift}.',
      details: {
        'planId': plan.id,
        'durationHours': plan.duration.inHours,
        'normalShift': currentShift,
        'setbackShift': plan.setbackShift,
        'preheatStartTime': plan.preheatStartTime.toIso8601String(),
      },
    );
    return applied;
  }

  Future<HolidayPlan> _applyRoomSetback(HolidayPlan plan, ECLProvider provider) async {
    final current = provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue;
    if (current == null) {
      throw const HolidayModeException(
        'Der aktuelle Raum-Sollwert ist nicht bekannt – ohne ihn könnte der '
        'Normalbetrieb später nicht korrekt wiederhergestellt werden.',
      );
    }
    final target = ((current - plan.roomSetbackKelvin) * 2).round() / 2;
    final clamped = target < minHolidayRoomSetpoint ? minHolidayRoomSetpoint : target;
    if (clamped >= current) {
      throw HolidayModeException(
        'Der Raum-Sollwert steht schon bei ${current.fixed(1)} °C – tiefer als '
        '${minHolidayRoomSetpoint.fixed(0)} °C senkt der Urlaubsmodus nicht.',
      );
    }
    try {
      await provider.writeParameter(ECLRegisters.roomTargetTemp, clamped);
    } catch (e) {
      throw HolidayModeException('Absenkung fehlgeschlagen: ${userFacingError(e)}');
    }
    final applied = plan.copyWith(
      normalRoomTemp: current,
      targetRoomTemp: clamped,
      setbackApplied: true,
      controlMode: 'room',
    );
    await provider.logService.logWrite(
      controllerId: provider.selectedControllerId,
      action: 'HOLIDAY_MODE_ACTIVATED',
      message:
          'Abwesenheitsmodus "${plan.title}" aktiv: Raum-Sollwert $current → $clamped °C.',
      details: {
        'planId': plan.id,
        'normalRoomTemp': current,
        'targetRoomTemp': clamped,
        'preheatStartTime': plan.preheatStartTime.toIso8601String(),
      },
    );
    return applied;
  }

  /// Ends a plan. If the setback was applied, the normal shift is written back
  /// first and the plan stays active if that fails. With [restore] = false the
  /// plan is closed without touching the controller (e.g. the user already
  /// reset it by hand).
  Future<HolidayPlan> cancelOrFinishPlan({
    required HolidayPlan plan,
    required ECLProvider provider,
    bool restore = true,
  }) async {
    final completed = plan.copyWith(isActive: false, isCompleted: true);

    if (plan.runsInController) {
      if (restore && plan.controllerSlot != null) {
        if (!provider.isConnected) {
          throw const HolidayModeException(
            'Keine Verbindung zum Regler – das Urlaubsprogramm im Regler konnte nicht gelöscht werden. '
            'Der Plan bleibt aktiv.',
          );
        }
        try {
          await provider.clearControllerHoliday(plan.controllerSlot!);
        } catch (e) {
          throw HolidayModeException('Löschen im Regler fehlgeschlagen: ${userFacingError(e)} Der Plan bleibt aktiv.');
        }
      }
      await savePlan(completed);
      await provider.logService.logWrite(
        controllerId: provider.selectedControllerId,
        action: 'HOLIDAY_MODE_DEACTIVATED',
        message: restore
            ? 'Abwesenheit "${plan.title}" beendet, Urlaubsprogramm P${plan.controllerSlot} im Regler gelöscht.'
            : 'Abwesenheit "${plan.title}" abgeschlossen.',
        details: {'planId': plan.id, 'slot': plan.controllerSlot},
      );
      return completed;
    }

    if (plan.setbackApplied && restore) {
      if (!provider.isConnected) {
        throw const HolidayModeException(
          'Keine Verbindung zum Regler – der Normalbetrieb konnte nicht '
          'wiederhergestellt werden. Der Plan bleibt aktiv.',
        );
      }
      try {
        if (plan.controlMode == 'room') {
          await provider.writeParameter(ECLRegisters.roomTargetTemp, plan.normalRoomTemp);
        } else {
          await provider.writeParameter(ECLRegisters.heatingCurveShift, plan.normalShift);
        }
      } catch (e) {
        throw HolidayModeException(
          'Wiederherstellen fehlgeschlagen: ${userFacingError(e)} Der Plan bleibt aktiv.',
        );
      }
    }

    await savePlan(completed);
    final restored = plan.setbackApplied && restore;
    await provider.logService.logWrite(
      controllerId: provider.selectedControllerId,
      action: restored
          ? 'HOLIDAY_MODE_DEACTIVATED'
          : 'HOLIDAY_MODE_CLOSED_WITHOUT_RESTORE',
      message: restored
          ? (plan.controlMode == 'room'
              ? 'Abwesenheitsmodus "${plan.title}" beendet. Raum-Sollwert zurück auf ${plan.normalRoomTemp} °C.'
              : 'Abwesenheitsmodus "${plan.title}" beendet. Parallelverschiebung zurück auf ${plan.normalShift}.')
          : 'Abwesenheitsmodus "${plan.title}" geschlossen, Regler nicht verändert.',
      details: {
        'planId': plan.id,
        'restoredShift': restored ? plan.normalShift : null,
      },
    );
    return completed;
  }

  /// Executes whatever the active plan is due for: apply the setback once the
  /// start has passed, restore normal operation once the preheat time has
  /// passed. Does nothing while the controller is unreachable, so a missed
  /// step is caught up on the next connected run. Returns the updated plan if
  /// something changed.
  Future<HolidayPlan?> runDueActions({
    required ECLProvider provider,
    DateTime? now,
  }) async {
    if (!provider.isConnected) return null;
    final at = now ?? DateTime.now();
    final plan = await getActivePlan();
    if (plan == null) return null;
    if (plan.runsInController) return _checkControllerPlan(plan, provider, at);

    final restoreDue = !at.isBefore(plan.preheatStartTime);
    if (restoreDue) {
      // Never lowered (e.g. phone was away the whole time): just close it.
      return cancelOrFinishPlan(
        plan: plan,
        provider: provider,
        restore: plan.setbackApplied,
      );
    }
    if (!plan.setbackApplied && !at.isBefore(plan.startDateTime)) {
      final applied = await _applySetback(plan, provider);
      await savePlan(applied);
      return applied;
    }
    return null;
  }

  /// A plan stored in the controller: the controller runs it; the app only
  /// closes it afterwards and reports if the controller lost it.
  Future<HolidayPlan?> _checkControllerPlan(HolidayPlan plan, ECLProvider provider, DateTime at) async {
    final slot = plan.controllerSlot;
    if (slot == null) return null;
    final List<ControllerHolidayEntry> entries;
    try {
      entries = await provider.readControllerHolidays();
    } catch (_) {
      return null;
    }
    final entry = entries.where((e) => e.slot == slot).firstOrNull;
    // the end the app wrote (midnight before the heat-up) – not the
    // controller's dates, which reset to 2015 when a schedule is deleted
    final heatUp = plan.preheatStartTime;
    final over = !at.isBefore(DateTime(heatUp.year, heatUp.month, heatUp.day));
    if (over) {
      // controller has resumed normal heating itself; tidy up the schedule
      try {
        if (entry != null && entry.isSet) await provider.clearControllerHoliday(slot);
      } catch (_) {}
      return cancelOrFinishPlan(plan: plan, provider: provider, restore: false);
    }
    if (entry == null || !entry.isSet) {
      final message = 'Urlaubsprogramm P$slot für "${plan.title}" ist nicht mehr im Regler – '
          'im Regler gelöscht oder geändert. Die Absenkung findet nicht statt.';
      await provider.logService.logError(
        action: 'APP_CHANGE_NOT_ON_DEVICE',
        message: message,
        controllerId: provider.selectedControllerId,
        category: ActivityLogCategory.controllerRead,
        errorCode: 'APP_CHANGE_NOT_ON_DEVICE',
        details: {'planId': plan.id, 'slot': slot},
      );
      await provider.alerts.raise(
        key: 'lost_holiday_${plan.id}',
        severity: AlertSeverity.error,
        title: 'Urlaub fehlt im Regler',
        message: message,
      );
      return cancelOrFinishPlan(plan: plan, provider: provider, restore: false);
    }
    return null;
  }
}
