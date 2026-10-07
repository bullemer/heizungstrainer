import 'dart:convert';

/// Represents a saved configuration snapshot / restore point of the heating controller.
class ConfigurationBackup {
  /// Unique identifier (UUID or timestamp millisecond string).
  final String id;

  /// Human-readable label (e.g., "Optimaler Winterbetrieb 2026").
  final String name;

  /// Timestamp when the backup was created.
  final DateTime timestamp;

  /// Heating curve parallel shift setpoint (-15 to +15, typical -3 to +3).
  final double heatingCurveShift;

  /// Target room temperature setpoint (if available, e.g. 20.0 °C).
  final double? roomTarget;

  /// Outdoor temperature at snapshot time (for reference).
  final double? outdoorTemp;

  /// Flow temperature at snapshot time.
  final double? flowTemp;

  /// Return temperature at snapshot time.
  final double? returnTemp;

  /// Optional user notes or explanation.
  final String? note;

  /// Whether this is a factory / pre-defined profile.
  final bool isPreset;

  /// What the backup controls: 'shift' (heating-curve shift) or 'room'
  /// (comfort room setpoint, for controllers without a writable shift).
  /// Backups from before 1.1.9 have none and are shift backups.
  final String controlMode;

  const ConfigurationBackup({
    required this.id,
    required this.name,
    required this.timestamp,
    required this.heatingCurveShift,
    this.roomTarget,
    this.outdoorTemp,
    this.flowTemp,
    this.returnTemp,
    this.note,
    this.isPreset = false,
    this.controlMode = 'shift',
  });

  bool get isRoomMode => controlMode == 'room';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'timestamp': timestamp.toIso8601String(),
        'heatingCurveShift': heatingCurveShift,
        'roomTarget': roomTarget,
        'outdoorTemp': outdoorTemp,
        'flowTemp': flowTemp,
        'returnTemp': returnTemp,
        'note': note,
        'isPreset': isPreset,
        'controlMode': controlMode,
      };

  factory ConfigurationBackup.fromJson(Map<String, dynamic> json) {
    return ConfigurationBackup(
      id: json['id'] as String,
      name: json['name'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      heatingCurveShift: (json['heatingCurveShift'] as num).toDouble(),
      roomTarget: (json['roomTarget'] as num?)?.toDouble(),
      outdoorTemp: (json['outdoorTemp'] as num?)?.toDouble(),
      flowTemp: (json['flowTemp'] as num?)?.toDouble(),
      returnTemp: (json['returnTemp'] as num?)?.toDouble(),
      note: json['note'] as String?,
      isPreset: json['isPreset'] as bool? ?? false,
      controlMode: json['controlMode'] as String? ?? 'shift',
    );
  }

  static List<ConfigurationBackup> decodeList(String rawJson) {
    try {
      final list = jsonDecode(rawJson) as List<dynamic>;
      return list
          .map((item) =>
              ConfigurationBackup.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<ConfigurationBackup> backups) {
    return jsonEncode(backups.map((b) => b.toJson()).toList());
  }

  /// Factory presets provided for quick 1-tap recovery.
  static List<ConfigurationBackup> get presets => presetsFor('shift');

  /// Presets for the controller's [controlMode] ('shift' or 'room').
  static List<ConfigurationBackup> presetsFor(String controlMode) {
    if (controlMode == 'room') {
      return [
        ConfigurationBackup(
          id: 'preset_room_standard',
          name: 'Werkseinstellung (20 °C)',
          timestamp: DateTime(2026, 1, 1),
          heatingCurveShift: 0.0,
          roomTarget: 20.0,
          note: 'Danfoss-Standard für den Komfort-Raumsollwert.',
          isPreset: true,
          controlMode: 'room',
        ),
        ConfigurationBackup(
          id: 'preset_room_eco',
          name: 'Eco-Sparbetrieb (19 °C)',
          timestamp: DateTime(2026, 1, 1),
          heatingCurveShift: 0.0,
          roomTarget: 19.0,
          note: 'Ca. 6 % weniger Heizenergie je Grad weniger Raumsoll.',
          isPreset: true,
          controlMode: 'room',
        ),
        ConfigurationBackup(
          id: 'preset_room_comfort',
          name: 'Komfortbetrieb (21 °C)',
          timestamp: DateTime(2026, 1, 1),
          heatingCurveShift: 0.0,
          roomTarget: 21.0,
          note: 'Etwas wärmer, z. B. für kalte Frosttage.',
          isPreset: true,
          controlMode: 'room',
        ),
      ];
    }
    return [
      ConfigurationBackup(
        id: 'preset_standard',
        name: 'Werkseinstellung (Danfoss Standard)',
        timestamp: DateTime(2026, 1, 1),
        heatingCurveShift: 0.0,
        roomTarget: 20.0,
        note: 'Empfohlene Grundeinstellung ohne Parallelverschiebung.',
        isPreset: true,
      ),
      ConfigurationBackup(
        id: 'preset_eco',
        name: 'Eco-Sparbetrieb (-2)',
        timestamp: DateTime(2026, 1, 1),
        heatingCurveShift: -2.0,
        roomTarget: 20.0,
        note: 'Ca. 12% Heizenergieersparnis für gut gedämmte Gebäude.',
        isPreset: true,
      ),
      ConfigurationBackup(
        id: 'preset_comfort',
        name: 'Komfortbetrieb (+1)',
        timestamp: DateTime(2026, 1, 1),
        heatingCurveShift: 1.0,
        roomTarget: 21.0,
        note: 'Höhere Vorlauftemperatur für kalte Frosttage.',
        isPreset: true,
      ),
    ];
  }
}
