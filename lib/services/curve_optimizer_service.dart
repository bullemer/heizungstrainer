import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// State of the step-by-step search for the lowest comfortable setpoint.
enum OptimizerPhase { idle, waiting, readyForFeedback, finished }

/// Persisted state of the optimisation assistant.
class OptimizerState {
  final bool active;
  final double? startSetpoint; // setpoint before the assistant changed anything
  final double? currentSetpoint; // setpoint of the step being tested
  final double? previousSetpoint; // last setpoint that was comfortable
  final DateTime? stepStartedAt;
  final double? resultSetpoint; // set when finished

  const OptimizerState({
    this.active = false,
    this.startSetpoint,
    this.currentSetpoint,
    this.previousSetpoint,
    this.stepStartedAt,
    this.resultSetpoint,
  });

  static const idle = OptimizerState();

  Map<String, dynamic> toJson() => {
        'active': active,
        'startSetpoint': startSetpoint,
        'currentSetpoint': currentSetpoint,
        'previousSetpoint': previousSetpoint,
        'stepStartedAt': stepStartedAt?.toIso8601String(),
        'resultSetpoint': resultSetpoint,
      };

  factory OptimizerState.fromJson(Map<String, dynamic> j) => OptimizerState(
        active: j['active'] as bool? ?? false,
        startSetpoint: (j['startSetpoint'] as num?)?.toDouble(),
        currentSetpoint: (j['currentSetpoint'] as num?)?.toDouble(),
        previousSetpoint: (j['previousSetpoint'] as num?)?.toDouble(),
        stepStartedAt: j['stepStartedAt'] == null ? null : DateTime.parse(j['stepStartedAt'] as String),
        resultSetpoint: (j['resultSetpoint'] as num?)?.toDouble(),
      );
}

/// Guides the EnergieSchweiz method: lower in small steps, observe for about
/// two days, stop one step before the coldest room gets too cold.
///
/// The assistant only decides *what* to suggest; the screen writes the
/// setpoint through the provider (licence, Beta gate and read-back apply).
class CurveOptimizerService {
  static const String storageKey = 'curve_optimizer_state';
  static const double stepKelvin = 0.5;
  static const double floorSetpoint = 18.0;
  static const Duration observation = Duration(hours: 48);

  /// Floor heating reacts slowly (screed storage), so each step is observed
  /// twice as long before asking for feedback.
  static const Duration observationFloor = Duration(hours: 96);

  static Duration observationFor({required bool floorHeating}) =>
      floorHeating ? observationFloor : observation;

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _inMemory;

  CurveOptimizerService({FlutterSecureStorage? storage, Map<String, String>? inMemoryStorage})
      : _storage = inMemoryStorage != null ? null : (storage ?? const FlutterSecureStorage()),
        _inMemory = inMemoryStorage;

  Future<OptimizerState> load() async {
    try {
      final raw = _inMemory != null ? _inMemory[storageKey] : await _storage!.read(key: storageKey);
      if (raw == null || raw.isEmpty) return OptimizerState.idle;
      return OptimizerState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[CurveOptimizer] Could not load state: $e');
      return OptimizerState.idle;
    }
  }

  Future<void> save(OptimizerState state) async {
    final raw = jsonEncode(state.toJson());
    if (_inMemory != null) {
      _inMemory[storageKey] = raw;
    } else {
      await _storage!.write(key: storageKey, value: raw);
    }
  }

  static OptimizerPhase phaseOf(OptimizerState s, DateTime now, {Duration wait = observation}) {
    if (s.resultSetpoint != null) return OptimizerPhase.finished;
    if (!s.active || s.stepStartedAt == null) return OptimizerPhase.idle;
    return now.difference(s.stepStartedAt!) >= wait
        ? OptimizerPhase.readyForFeedback
        : OptimizerPhase.waiting;
  }

  /// Next setpoint to try from [current], or null if the floor is reached.
  static double? nextStep(double current) {
    final next = ((current - stepKelvin) * 2).round() / 2;
    return next < floorSetpoint ? null : next;
  }

  /// State after the first step to [firstStep] was written successfully.
  static OptimizerState started({required double from, required double firstStep, required DateTime now}) =>
      OptimizerState(
        active: true,
        startSetpoint: from,
        previousSetpoint: from,
        currentSetpoint: firstStep,
        stepStartedAt: now,
      );

  /// "Comfortable" feedback: continue with [nextSetpoint] (already written),
  /// or finish at the current setpoint if there is no further step.
  static OptimizerState comfortable(OptimizerState s, {double? nextSetpoint, required DateTime now}) {
    if (nextSetpoint == null) {
      return OptimizerState(startSetpoint: s.startSetpoint, resultSetpoint: s.currentSetpoint);
    }
    return OptimizerState(
      active: true,
      startSetpoint: s.startSetpoint,
      previousSetpoint: s.currentSetpoint,
      currentSetpoint: nextSetpoint,
      stepStartedAt: now,
    );
  }

  /// "Too cold" feedback: the previous step is the result (the screen writes
  /// it back to the controller).
  static OptimizerState tooCold(OptimizerState s) =>
      OptimizerState(startSetpoint: s.startSetpoint, resultSetpoint: s.previousSetpoint);
}
