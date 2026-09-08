import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';

/// Manages persistent storage and hardware execution of holiday & absence mode.
class HolidayService {
  static const String _storageKey = 'ecl_holiday_plans';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _inMemory;

  HolidayService({
    FlutterSecureStorage? storage,
    Map<String, String>? inMemoryStorage,
  })  : _storage = inMemoryStorage != null
            ? null
            : (storage ?? const FlutterSecureStorage()),
        _inMemory = inMemoryStorage;

  /// Retrieves all holiday plans from storage, sorted newest first.
  Future<List<HolidayPlan>> getAllPlans() async {
    final inMem = _inMemory;
    if (inMem != null) {
      final raw = inMem[_storageKey];
      if (raw == null || raw.isEmpty) return [];
      final list = HolidayPlan.decodeList(raw);
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    }

    try {
      final raw = await _storage!
          .read(key: _storageKey)
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
      if (raw == null || raw.isEmpty) {
        return [];
      }
      final list = HolidayPlan.decodeList(raw);
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
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
    final existing = await getAllPlans();
    final updated = [plan, ...existing.where((p) => p.id != plan.id)];
    final encoded = HolidayPlan.encodeList(updated);

    final inMem = _inMemory;
    if (inMem != null) {
      inMem[_storageKey] = encoded;
      return;
    }
    await _storage!.write(key: _storageKey, value: encoded);
  }

  /// Deletes a plan by ID.
  Future<void> deletePlan(String id) async {
    final existing = await getAllPlans();
    final updated = existing.where((p) => p.id != id).toList();
    final encoded = HolidayPlan.encodeList(updated);

    final inMem = _inMemory;
    if (inMem != null) {
      inMem[_storageKey] = encoded;
      return;
    }
    await _storage!.write(key: _storageKey, value: encoded);
  }

  /// Calculates estimated energy and cost savings for an absence period.
  Map<String, double> calculateSavings({
    required Duration duration,
    double setbackDiff = 5.0, // e.g. 21°C -> 16°C
    double pricePerKwh = 0.13, // average gas/heat price
  }) {
    final hours = duration.inHours.toDouble();
    if (hours <= 0) return {'kwh': 0.0, 'euro': 0.0};

    // Baseline heat load: ~2.5 kW for average residential unit during heating season
    // ~6% savings per 1°C setback reduction
    final savingsFactor = (setbackDiff * 0.06).clamp(0.05, 0.40);
    final kwhSaved = hours * 2.5 * savingsFactor;
    final euroSaved = kwhSaved * pricePerKwh;

    return {
      'kwh': double.parse(kwhSaved.toStringAsFixed(1)),
      'euro': double.parse(euroSaved.toStringAsFixed(2)),
    };
  }

  /// Activates a holiday plan: captures current controller state, applies setback,
  /// and persists the plan.
  Future<HolidayPlan> activatePlan({
    required HolidayPlan plan,
    required ECLProvider provider,
  }) async {
    // Capture previous baseline settings
    final currentShift = provider
            .getReading(ECLRegisters.heatingCurveShift)
            ?.displayValue ??
        0.0;
    final currentRoom =
        provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue ?? 21.0;

    final updatedPlan = plan.copyWith(
      normalShift: currentShift,
      normalRoomTemp: currentRoom,
      isActive: true,
      isCompleted: false,
    );

    // Apply setback shift to hardware controller if connected
    if (provider.isConnected) {
      try {
        await provider.writeParameter(
          ECLRegisters.heatingCurveShift,
          updatedPlan.setbackShift,
        );
      } catch (_) {
        // Fallback for offline/simulated or write issues
      }
    }

    await savePlan(updatedPlan);

    await provider.logService.logWrite(
      controllerId: provider.selectedControllerId,
      action: 'HOLIDAY_MODE_ACTIVATED',
      message:
          'Abwesenheitsmodus "${updatedPlan.title}" aktiviert. Vorlauf abgesenkt auf Shift ${updatedPlan.setbackShift}.',
      details: {
        'planId': updatedPlan.id,
        'durationHours': updatedPlan.duration.inHours,
        'setbackShift': updatedPlan.setbackShift,
        'preheatStartTime': updatedPlan.preheatStartTime.toIso8601String(),
      },
    );

    return updatedPlan;
  }

  /// Cancels or finishes a holiday plan and restores normal comfort settings.
  Future<HolidayPlan> cancelOrFinishPlan({
    required HolidayPlan plan,
    required ECLProvider provider,
  }) async {
    final updatedPlan = plan.copyWith(
      isActive: false,
      isCompleted: true,
    );

    // Restore original comfort shift if connected
    if (provider.isConnected) {
      try {
        await provider.writeParameter(
          ECLRegisters.heatingCurveShift,
          updatedPlan.normalShift,
        );
      } catch (_) {
        // Fallback
      }
    }

    await savePlan(updatedPlan);

    await provider.logService.logWrite(
      controllerId: provider.selectedControllerId,
      action: 'HOLIDAY_MODE_DEACTIVATED',
      message:
          'Abwesenheitsmodus "${updatedPlan.title}" beendet. Normalbetrieb wiederhergestellt (Shift ${updatedPlan.normalShift}).',
      details: {
        'planId': updatedPlan.id,
        'restoredShift': updatedPlan.normalShift,
      },
    );

    return updatedPlan;
  }
}
