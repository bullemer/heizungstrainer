import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Predefined presets for NIBE heat pumps using Modbus TCP.
class NibeModbusPreset {
  final String id;
  final String name;
  final String description;
  final int defaultPort;
  final int defaultUnitId;
  final int outdoorRegister;
  final int flowRegister;
  final int returnRegister;
  final int hotWaterRegister;
  final int? roomTargetRegister;
  final int? heatingCurveShiftRegister;
  final double multiplier;
  final bool isHoldingRegister;

  const NibeModbusPreset({
    required this.id,
    required this.name,
    required this.description,
    this.defaultPort = 502,
    this.defaultUnitId = 1,
    required this.outdoorRegister,
    required this.flowRegister,
    required this.returnRegister,
    required this.hotWaterRegister,
    this.roomTargetRegister,
    this.heatingCurveShiftRegister,
    this.multiplier = 0.1,
    this.isHoldingRegister = true,
  });
}

/// Configuration model for NIBE heat pumps communicating via Modbus TCP.
///
/// Supports NIBE S-Series (native Modbus TCP in menu 7.5.9) and
/// NIBE F-Series (with NIBE Modbus 40 accessory module).
class NibeModbusConfig {
  static const String storageKey = 'nibe_modbus_config';

  final String host;
  final int port;
  final int unitId;
  final int outdoorRegister;
  final int flowRegister;
  final int returnRegister;
  final int hotWaterRegister;
  final int? roomTargetRegister;
  final int? heatingCurveShiftRegister;
  final double multiplier;

  /// Register type of the four SENSOR registers (false = input registers,
  /// FC04). Room target and curve shift are always holding registers.
  final bool isHoldingRegister;

  /// Write with FC 0x10 (write multiple) instead of FC 0x06: MODBUS 40
  /// (F series / SMO) only implements FC 0x03 and 0x10.
  bool get writeMultiple => _modbus40Presets.contains(presetId);
  final String presetId;
  final String presetName;

  static const List<NibeModbusPreset> presets = [
    // NIBE "Modbus S-series" register list: the sensors are INPUT registers
    // (FC04, address = NIBE ID, s16 ÷10): 1 BT1, 5 BT2, 7 BT3, 8 BT7, 9 BT6.
    // Holding 30 = curve offset climate system 1 (−10..10, whole steps).
    // Holding 26 is the heating CURVE number (0–15), not a room setpoint – it
    // was wrongly used as room target up to 1.2.10 and must never be written
    // with a temperature. No verified room setpoint register → disabled.
    NibeModbusPreset(
      id: 'nibe_s_series',
      name: 'NIBE S-Serie (S1155 / S1255 / S2125 / VVM S320)',
      description: 'Natives Modbus TCP (Menü 7.5.9). Eingangsregister BT1=1, BT2=5, BT3=7, BT7=8; '
          'Kurvenverschiebung = Halteregister 30 (ganze Stufen −10…10)',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 1,
      flowRegister: 5,
      returnRegister: 7,
      hotWaterRegister: 8,
      roomTargetRegister: null,
      heatingCurveShiftRegister: 30,
      multiplier: 0.1,
      isHoldingRegister: false,
    ),
    NibeModbusPreset(
      id: 'nibe_f_series_modbus40',
      name: 'NIBE F-Serie (F1155 / F1255 mit Modbus 40)',
      description: 'MODBUS 40 ist Modbus RTU (RS-485): es braucht einen RS-485→Modbus-TCP-Wandler. '
          'BT1=40004, BT2=40008, BT3=40012, BT7=40013, Offset S1=47011',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 40004,
      flowRegister: 40008,
      returnRegister: 40012,
      hotWaterRegister: 40013,
      // 47011 = "Heat Offset S1" (whole steps). 47007 is the curve *slope* and must
      // not be written as a shift. Room setpoint register not verified -> disabled.
      roomTargetRegister: null,
      heatingCurveShiftRegister: 47011,
      multiplier: 0.1,
      isHoldingRegister: true,
    ),
    NibeModbusPreset(
      id: 'nibe_smo40',
      name: 'NIBE SMO 20 / 40 (Modbus 40)',
      description: 'NIBE Regelgerät für Luft-Wasser-Wärmepumpen (F2120 / F2040); MODBUS 40 ist Modbus RTU '
          '(RS-485) und braucht einen RS-485→Modbus-TCP-Wandler',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 40004,
      flowRegister: 40008,
      returnRegister: 40012,
      hotWaterRegister: 40013,
      // 47011 = "Heat Offset S1" (whole steps). 47007 is the curve *slope* and must
      // not be written as a shift. Room setpoint register not verified -> disabled.
      roomTargetRegister: null,
      heatingCurveShiftRegister: 47011,
      multiplier: 0.1,
      isHoldingRegister: true,
    ),
    NibeModbusPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Individuelle Registeradressen und Modbus-Parameter für NIBE',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 1,
      flowRegister: 5,
      returnRegister: 7,
      hotWaterRegister: 8,
      roomTargetRegister: null,
      heatingCurveShiftRegister: 30,
      multiplier: 0.1,
      isHoldingRegister: false,
    ),
  ];

  const NibeModbusConfig({
    this.host = '192.168.1.160',
    this.port = 502,
    this.unitId = 1,
    this.outdoorRegister = 1,
    this.flowRegister = 5,
    this.returnRegister = 7,
    this.hotWaterRegister = 8,
    this.roomTargetRegister,
    this.heatingCurveShiftRegister = 30,
    this.multiplier = 0.1,
    this.isHoldingRegister = false,
    this.presetId = 'nibe_s_series',
    this.presetName = 'NIBE S-Serie (S1155 / S1255 / S2125 / VVM S320)',
  });

  factory NibeModbusConfig.fromPreset(
    NibeModbusPreset preset, {
    String host = '192.168.1.160',
  }) {
    return NibeModbusConfig(
      host: host,
      port: preset.defaultPort,
      unitId: preset.defaultUnitId,
      outdoorRegister: preset.outdoorRegister,
      flowRegister: preset.flowRegister,
      returnRegister: preset.returnRegister,
      hotWaterRegister: preset.hotWaterRegister,
      roomTargetRegister: preset.roomTargetRegister,
      heatingCurveShiftRegister: preset.heatingCurveShiftRegister,
      multiplier: preset.multiplier,
      isHoldingRegister: preset.isHoldingRegister,
      presetId: preset.id,
      presetName: preset.name,
    );
  }

  NibeModbusConfig copyWith({
    String? host,
    int? port,
    int? unitId,
    int? outdoorRegister,
    int? flowRegister,
    int? returnRegister,
    int? hotWaterRegister,
    int? roomTargetRegister,
    int? heatingCurveShiftRegister,
    double? multiplier,
    bool? isHoldingRegister,
    String? presetId,
    String? presetName,
  }) {
    return NibeModbusConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      unitId: unitId ?? this.unitId,
      outdoorRegister: outdoorRegister ?? this.outdoorRegister,
      flowRegister: flowRegister ?? this.flowRegister,
      returnRegister: returnRegister ?? this.returnRegister,
      hotWaterRegister: hotWaterRegister ?? this.hotWaterRegister,
      roomTargetRegister: roomTargetRegister ?? this.roomTargetRegister,
      heatingCurveShiftRegister:
          heatingCurveShiftRegister ?? this.heatingCurveShiftRegister,
      multiplier: multiplier ?? this.multiplier,
      isHoldingRegister: isHoldingRegister ?? this.isHoldingRegister,
      presetId: presetId ?? this.presetId,
      presetName: presetName ?? this.presetName,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'unitId': unitId,
        'outdoorRegister': outdoorRegister,
        'flowRegister': flowRegister,
        'returnRegister': returnRegister,
        'hotWaterRegister': hotWaterRegister,
        'roomTargetRegister': roomTargetRegister,
        'heatingCurveShiftRegister': heatingCurveShiftRegister,
        'multiplier': multiplier,
        'isHoldingRegister': isHoldingRegister,
        'presetId': presetId,
        'presetName': presetName,
      };

  /// MODBUS 40 presets; they shipped (<= 1.1.0) with shift=47007 (curve slope) and room=47011.
  static const _modbus40Presets = {'nibe_f_series_modbus40', 'nibe_smo40'};

  static int? _optionalRegister(Map<String, dynamic> json, String key, int? fallback) {
    if (!json.containsKey(key)) return fallback;
    return (json[key] as num?)?.toInt();
  }

  factory NibeModbusConfig.fromJson(Map<String, dynamic> json) {
    final presetId = json['presetId'] as String? ?? 'nibe_s_series';
    final isModbus40 = _modbus40Presets.contains(presetId);
    var roomTargetRegister = _optionalRegister(json, 'roomTargetRegister', null);
    var shiftRegister = _optionalRegister(json, 'heatingCurveShiftRegister', 30);
    var isHolding = json['isHoldingRegister'] as bool? ?? !_isSSeries(presetId);
    if (isModbus40 && shiftRegister == 47007) {
      shiftRegister = 47011;
      roomTargetRegister = null;
    }
    // <= 1.2.10 shipped the S-series (and custom default) map with the sensors
    // as holding registers and "room target" on holding 26, which is the
    // heating curve number. Repair stored configs.
    if (!isModbus40 && roomTargetRegister == 26) roomTargetRegister = null;
    if (presetId == 'nibe_s_series') isHolding = false;
    return NibeModbusConfig(
      host: json['host'] as String? ?? '192.168.1.160',
      port: (json['port'] as num?)?.toInt() ?? 502,
      unitId: (json['unitId'] as num?)?.toInt() ?? 1,
      outdoorRegister: (json['outdoorRegister'] as num?)?.toInt() ?? 1,
      flowRegister: (json['flowRegister'] as num?)?.toInt() ?? 5,
      returnRegister: (json['returnRegister'] as num?)?.toInt() ?? 7,
      hotWaterRegister: (json['hotWaterRegister'] as num?)?.toInt() ?? 8,
      roomTargetRegister: roomTargetRegister,
      heatingCurveShiftRegister: shiftRegister,
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 0.1,
      isHoldingRegister: isHolding,
      presetId: presetId,
      presetName: json['presetName'] as String? ??
          'NIBE S-Serie (S1155 / S1255 / S2125 / VVM S320)',
    );
  }

  static bool _isSSeries(String presetId) => presetId == 'nibe_s_series' || presetId == 'custom';

  static Future<NibeModbusConfig> load(FlutterSecureStorage storage) async {
    try {
      final raw = await storage.read(key: storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return NibeModbusConfig.fromJson(decoded);
      }
    } catch (_) {}
    return const NibeModbusConfig();
  }

  Future<void> save(FlutterSecureStorage storage) async {
    try {
      await storage.write(key: storageKey, value: jsonEncode(toJson()));
    } catch (_) {}
  }
}
