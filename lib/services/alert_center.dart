import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AlertSeverity { error, warning, info }

/// One message in "Aktive Meldungen".
///
/// A *condition* (controller alarm, sensor fault) stays listed while it is
/// active and disappears when it resolves. An *event* (lost app change,
/// change outside the app, unconfirmed write) stays until acknowledged.
class AppAlert {
  AppAlert({
    required this.key,
    required this.severity,
    required this.title,
    required this.message,
    required this.isCondition,
    required this.firstAt,
    required this.lastAt,
    this.acknowledged = false,
  });

  final String key;
  final AlertSeverity severity;
  final String title;
  final String message;
  final bool isCondition;
  final DateTime firstAt;
  DateTime lastAt;
  bool acknowledged;

  Map<String, dynamic> toJson() => {
        'k': key,
        's': severity.name,
        't': title,
        'm': message,
        'c': isCondition,
        'f': firstAt.toIso8601String(),
        'l': lastAt.toIso8601String(),
        'a': acknowledged,
      };

  static AppAlert? fromJson(Object? j) {
    if (j is! Map) return null;
    final first = DateTime.tryParse('${j['f']}');
    final last = DateTime.tryParse('${j['l']}');
    if (j['k'] is! String || first == null || last == null) return null;
    return AppAlert(
      key: j['k'] as String,
      severity: AlertSeverity.values.firstWhere((s) => s.name == j['s'], orElse: () => AlertSeverity.warning),
      title: '${j['t']}',
      message: '${j['m']}',
      isCondition: j['c'] == true,
      firstAt: first,
      lastAt: last,
      acknowledged: j['a'] == true,
    );
  }
}

/// Holds the active alerts shown at the top of the Logs tab; persisted so
/// they survive an app restart. The full history stays in the activity log.
class AlertCenter extends ChangeNotifier {
  AlertCenter({FlutterSecureStorage? storage, Map<String, String>? inMemoryStorage})
      : _memory = inMemoryStorage,
        _storage = inMemoryStorage != null ? null : (storage ?? const FlutterSecureStorage());

  static const storageKey = 'ht_active_alerts';
  static const maxAlerts = 50;

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;
  final List<AppAlert> _alerts = [];
  bool _loaded = false;

  /// Newest first.
  List<AppAlert> get alerts => List.unmodifiable(_alerts);

  /// Number of alerts not yet acknowledged (badge on the Logs tab).
  int get unacknowledgedCount => _alerts.where((a) => !a.acknowledged).length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = _memory != null ? _memory[storageKey] : await _storage!.read(key: storageKey);
    if (raw == null) return;
    try {
      for (final j in jsonDecode(raw) as List) {
        final a = AppAlert.fromJson(j);
        if (a != null && !_alerts.any((x) => x.key == a.key)) _alerts.add(a);
      }
      notifyListeners();
    } catch (_) {
      // corrupt → start empty
    }
  }

  Future<void> _save() async {
    final raw = jsonEncode(_alerts.map((a) => a.toJson()).toList());
    if (_memory != null) {
      _memory[storageKey] = raw;
    } else {
      try {
        await _storage!.write(key: storageKey, value: raw);
      } catch (e) {
        debugPrint('[Alerts] could not persist: $e');
      }
    }
  }

  /// Adds or refreshes an alert. A condition that is already listed only
  /// updates its time (no new badge); a new one is unacknowledged.
  Future<void> raise({
    required String key,
    required AlertSeverity severity,
    required String title,
    required String message,
    bool isCondition = false,
    DateTime? now,
  }) async {
    await load();
    final at = now ?? DateTime.now();
    final existing = _alerts.where((a) => a.key == key).firstOrNull;
    if (existing != null && existing.isCondition) {
      existing.lastAt = at;
      notifyListeners();
      return;
    }
    _alerts.removeWhere((a) => a.key == key);
    _alerts.insert(
      0,
      AppAlert(
        key: key,
        severity: severity,
        title: title,
        message: message,
        isCondition: isCondition,
        firstAt: at,
        lastAt: at,
      ),
    );
    while (_alerts.length > maxAlerts) {
      _alerts.removeLast();
    }
    notifyListeners();
    await _save();
  }

  /// A condition is over (alarm cleared, sensor back).
  Future<void> resolve(String key) async {
    await load();
    final before = _alerts.length;
    _alerts.removeWhere((a) => a.key == key && a.isCondition);
    if (_alerts.length == before) return;
    notifyListeners();
    await _save();
  }

  /// "Gesehen": events disappear, conditions stay listed but lose the badge.
  Future<void> acknowledge(String key) async {
    final a = _alerts.where((a) => a.key == key).firstOrNull;
    if (a == null) return;
    if (a.isCondition) {
      a.acknowledged = true;
    } else {
      _alerts.remove(a);
    }
    notifyListeners();
    await _save();
  }

  Future<void> acknowledgeAll() async {
    _alerts.removeWhere((a) => !a.isCondition);
    for (final a in _alerts) {
      a.acknowledged = true;
    }
    notifyListeners();
    await _save();
  }
}
