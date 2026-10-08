import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/week_schedule.dart';

/// Who set a known value last.
enum SettingSource { app, controller }

/// A setting value the app knows, and where it came from.
class KnownSetting {
  const KnownSetting(this.value, this.source, this.at);

  final double value;
  final SettingSource source;
  final DateTime at;

  Map<String, dynamic> toJson() => {'v': value, 's': source.name, 'at': at.toIso8601String()};

  static KnownSetting? fromJson(Object? json) {
    if (json is! Map) return null;
    final v = json['v'];
    final at = DateTime.tryParse('${json['at']}');
    if (v is! num || at == null) return null;
    return KnownSetting(v.toDouble(), json['s'] == 'app' ? SettingSource.app : SettingSource.controller, at);
  }
}

/// One setting where the controller differs from what the app knew.
class SettingDiff {
  const SettingDiff({required this.parameter, required this.known, required this.live});

  final ECLParameter parameter;
  final KnownSetting known;
  final double live;

  /// The app wrote [known] itself – the controller no longer has it.
  bool get appChangeMissing => known.source == SettingSource.app;
}

/// One row of a full settings check (app's last known value vs. controller).
class SettingCheckRow {
  const SettingCheckRow({required this.parameter, required this.known, required this.live});

  final ECLParameter parameter;
  final KnownSetting? known;
  final double? live;

  bool get differs => known != null && live != null && !ControllerSettingsWatch.same(known!.value, live!);
}

/// Remembers the controller's settings (curve, setpoints) and reports when
/// the controller no longer matches: changes made outside the app (on the
/// controller, Danfoss app/portal) and – as an error – values the app wrote
/// that the controller doesn't show any more.
class ControllerSettingsWatch {
  ControllerSettingsWatch({FlutterSecureStorage? storage, Map<String, String>? inMemoryStorage})
      : _memory = inMemoryStorage,
        _storage = inMemoryStorage != null ? null : (storage ?? const FlutterSecureStorage());

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;

  /// Settings that are compared (sensors are not – they change constantly).
  static const List<ECLParameter> tracked = [
    ...ECLRegisters.writableParameters,
    ...ECLRegisters.curveParameters,
    ...ECLRegisters.extraSettings,
    ...ECLRegisters.dhwSettings,
  ];

  static String storageKey(String controllerId) => 'controller_known_settings_$controllerId';

  static bool same(double a, double b) => (a - b).abs() < 0.05;

  final Map<String, Map<String, KnownSetting>> _cache = {};

  Future<Map<String, KnownSetting>> _load(String controllerId) async {
    final cached = _cache[controllerId];
    if (cached != null) return cached;
    final key = storageKey(controllerId);
    final raw = _memory != null ? _memory[key] : await _storage!.read(key: key);
    final result = <String, KnownSetting>{};
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((id, v) {
          final k = KnownSetting.fromJson(v);
          if (k != null) result[id] = k;
        });
      } on FormatException {
        // corrupt → start a new baseline
      }
    }
    return _cache[controllerId] = result;
  }

  Future<void> _save(String controllerId) async {
    final raw = jsonEncode(_cache[controllerId]!.map((k, v) => MapEntry(k, v.toJson())));
    final key = storageKey(controllerId);
    if (_memory != null) {
      _memory[key] = raw;
    } else {
      await _storage!.write(key: key, value: raw);
    }
  }

  /// Snapshot of what the app currently knows for [controllerId].
  Future<Map<String, KnownSetting>> known(String controllerId) async =>
      Map.of(await _load(controllerId));

  /// The app wrote [value] and the controller confirmed it.
  Future<void> recordAppWrite(String controllerId, ECLParameter parameter, double value, {DateTime? now}) async {
    final known = await _load(controllerId);
    known[parameter.id] = KnownSetting(value, SettingSource.app, now ?? DateTime.now());
    await _save(controllerId);
  }

  /// Compares [live] controller values (by parameter id) with what the app
  /// knew, returns the differences and adopts the live values as the new
  /// baseline. Settings seen for the first time are only recorded.
  Future<List<SettingDiff>> compare(String controllerId, Map<String, double> live, {DateTime? now}) async {
    final known = await _load(controllerId);
    final at = now ?? DateTime.now();
    final diffs = <SettingDiff>[];
    var changed = false;
    for (final p in tracked) {
      final value = live[p.id];
      if (value == null) continue;
      final before = known[p.id];
      if (before != null && same(before.value, value)) continue;
      if (before != null) diffs.add(SettingDiff(parameter: p, known: before, live: value));
      known[p.id] = KnownSetting(value, SettingSource.controller, at);
      changed = true;
    }
    if (changed) await _save(controllerId);
    return diffs;
  }

  // ── Controller alarms ──────────────────────────────────────────────

  static String alarmKey(String controllerId) => 'controller_active_alarms_$controllerId';

  /// Alarm numbers (1–32) set in [mask].
  static Set<int> alarmsIn(int mask) => {for (var i = 0; i < 32; i++) if (mask & (1 << i) != 0) i + 1};

  /// Compares the controller's active alarms with the last known ones and
  /// stores the new state. Returns (raised, cleared, stillActive).
  Future<({Set<int> raised, Set<int> cleared, Set<int> stillActive})> updateAlarms(
      String controllerId, Set<int> active) async {
    final key = alarmKey(controllerId);
    final raw = _memory != null ? _memory[key] : await _storage!.read(key: key);
    final before = <int>{
      for (final part in (raw ?? '').split(','))
        if (int.tryParse(part) != null) int.parse(part),
    };
    final value = (active.toList()..sort()).join(',');
    if (value != raw) {
      if (_memory != null) {
        _memory[key] = value;
      } else {
        await _storage!.write(key: key, value: value);
      }
    }
    return (
      raised: active.difference(before),
      cleared: before.difference(active),
      stillActive: active.intersection(before),
    );
  }

  // ── Weekly schedule ────────────────────────────────────────────────

  static String scheduleKey(String controllerId) => 'controller_schedule_$controllerId';

  /// Last known schedule and whether the app wrote it.
  Future<({WeekSchedule? schedule, bool byApp})> knownSchedule(String controllerId) async {
    final key = scheduleKey(controllerId);
    final raw = _memory != null ? _memory[key] : await _storage!.read(key: key);
    if (raw == null) return (schedule: null, byApp: false);
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return (schedule: WeekSchedule.decode(map['s'] as String?), byApp: map['src'] == 'app');
    } catch (_) {
      return (schedule: null, byApp: false);
    }
  }

  Future<void> saveSchedule(String controllerId, WeekSchedule schedule, {required bool byApp}) async {
    final raw = jsonEncode({'src': byApp ? 'app' : 'controller', 's': schedule.encode()});
    final key = scheduleKey(controllerId);
    if (_memory != null) {
      _memory[key] = raw;
    } else {
      await _storage!.write(key: key, value: raw);
    }
  }
}
