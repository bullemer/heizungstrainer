import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The normal app changes settings on ONE controller – the first one it
/// connects to ("dein Regler"). Other controllers can be viewed but not
/// changed; a Master licence lifts this. Switching to another controller is
/// possible once every 12 months (new controller, move). Stored on the phone
/// only (by decision: no server check).
class ControllerBinding {
  const ControllerBinding({
    required this.identity,
    required this.label,
    required this.boundAt,
    this.changedAt,
  });

  /// Stable id, e.g. "danfoss:087H3040:2-39732" or "vaillant_ebusd@192.168.1.20".
  final String identity;

  /// Human-readable, e.g. "Danfoss ECL Comfort 310 · Serien-Nr. 2-39732".
  final String label;
  final DateTime boundAt;

  /// Last time the user switched to another controller (null = never).
  final DateTime? changedAt;

  static const changeInterval = Duration(days: 365);

  /// When the next switch is allowed (null = now).
  DateTime? nextChangeAllowed(DateTime now) {
    final c = changedAt;
    if (c == null) return null;
    final next = c.add(changeInterval);
    return next.isAfter(now) ? next : null;
  }

  Map<String, dynamic> toJson() => {
        'id': identity,
        'label': label,
        'boundAt': boundAt.toIso8601String(),
        'changedAt': changedAt?.toIso8601String(),
      };

  static ControllerBinding? fromJson(Object? j) {
    if (j is! Map) return null;
    final bound = DateTime.tryParse('${j['boundAt']}');
    if (j['id'] is! String || bound == null) return null;
    return ControllerBinding(
      identity: j['id'] as String,
      label: '${j['label'] ?? j['id']}',
      boundAt: bound,
      changedAt: j['changedAt'] == null ? null : DateTime.tryParse('${j['changedAt']}'),
    );
  }
}

enum ControllerAccess {
  /// Not determined yet (connecting) or not connected.
  unknown,

  /// Demo/simulation or Master licence: no restriction.
  unrestricted,

  /// The bound controller (or just bound now).
  own,

  /// Another controller: read only.
  foreign,
}

class ControllerBindingStore {
  ControllerBindingStore({FlutterSecureStorage? storage, Map<String, String>? inMemoryStorage})
      : _memory = inMemoryStorage,
        _storage = inMemoryStorage != null ? null : (storage ?? const FlutterSecureStorage());

  static const storageKey = 'ht_controller_binding';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;

  Future<ControllerBinding?> load() async {
    final raw = _memory != null ? _memory[storageKey] : await _storage!.read(key: storageKey);
    if (raw == null) return null;
    try {
      return ControllerBinding.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ControllerBinding b) async {
    final raw = jsonEncode(b.toJson());
    if (_memory != null) {
      _memory[storageKey] = raw;
    } else {
      await _storage!.write(key: storageKey, value: raw);
    }
  }
}
