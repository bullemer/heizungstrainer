import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Predefined configuration presets for popular Modbus-capable heating controllers.
class GenericModbusPreset {
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

  const GenericModbusPreset({
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

/// Configuration model for a Generic Modbus TCP heating controller.
///
/// Enables users with any Modbus-TCP-compatible heating system (e.g. Technische Alternative
/// UVR16x2 / C.M.I., Siemens Synco, Wolf BM-2, Luxtronik, Stiebel Eltron) to connect
/// their real hardware by defining register addresses and scaling multipliers.
class GenericModbusConfig {
  static const String storageKey = 'generic_modbus_config';

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
  final bool isHoldingRegister;
  final String presetId;
  final String presetName;

  static const List<GenericModbusPreset> presets = [
    GenericModbusPreset(
      id: 'standard',
      name: 'Standard Modbus Heizung',
      description: 'Standardbelegung (1=Außen, 2=Vorlauf, 3=Rücklauf, 4=Warmwasser, 5=Sollwert), Faktor 0.1',
      outdoorRegister: 1,
      flowRegister: 2,
      returnRegister: 3,
      hotWaterRegister: 4,
      roomTargetRegister: 5,
      heatingCurveShiftRegister: 6,
      multiplier: 0.1,
    ),
    GenericModbusPreset(
      id: 'ta_cmi',
      name: 'Technische Alternative (UVR16x2 / C.M.I.)',
      description: 'C.M.I. Modbus-TCP Weiterleitung der Sensoreingänge S1 bis S4, Faktor 0.1',
      outdoorRegister: 1,
      flowRegister: 2,
      returnRegister: 3,
      hotWaterRegister: 4,
      roomTargetRegister: 5,
      multiplier: 0.1,
    ),
    GenericModbusPreset(
      id: 'siemens_synco',
      name: 'Siemens Synco 700 / OZW772',
      description: 'Siemens Primär- und Heizkreis-Standardregister (10=Außen, 11=Vorlauf, 12=Rücklauf), Faktor 0.1',
      outdoorRegister: 10,
      flowRegister: 11,
      returnRegister: 12,
      hotWaterRegister: 15,
      roomTargetRegister: 20,
      multiplier: 0.1,
    ),
    GenericModbusPreset(
      id: 'wolf_bm2',
      name: 'Wolf Heizung (BM-2 / ISM7 Modbus)',
      description: 'Wolf Modbus TCP Interface (100=Außen, 101=Vorlauf, 102=Rücklauf, 103=Warmwasser), Faktor 0.1',
      outdoorRegister: 100,
      flowRegister: 101,
      returnRegister: 102,
      hotWaterRegister: 103,
      roomTargetRegister: 105,
      multiplier: 0.1,
    ),
    GenericModbusPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Vollständig freie Konfiguration aller Register und Parameter',
      outdoorRegister: 1,
      flowRegister: 2,
      returnRegister: 3,
      hotWaterRegister: 4,
      roomTargetRegister: 5,
      heatingCurveShiftRegister: 6,
      multiplier: 0.1,
    ),
  ];

  const GenericModbusConfig({
    this.host = '192.168.1.50',
    this.port = 502,
    this.unitId = 1,
    this.outdoorRegister = 1,
    this.flowRegister = 2,
    this.returnRegister = 3,
    this.hotWaterRegister = 4,
    this.roomTargetRegister = 5,
    this.heatingCurveShiftRegister = 6,
    this.multiplier = 0.1,
    this.isHoldingRegister = true,
    this.presetId = 'standard',
    this.presetName = 'Standard Modbus Heizung',
  });

  factory GenericModbusConfig.fromPreset(GenericModbusPreset preset, {String host = '192.168.1.50'}) {
    return GenericModbusConfig(
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

  GenericModbusConfig copyWith({
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
    return GenericModbusConfig(
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

  factory GenericModbusConfig.fromJson(Map<String, dynamic> json) {
    return GenericModbusConfig(
      host: json['host'] as String? ?? '192.168.1.50',
      port: (json['port'] as num?)?.toInt() ?? 502,
      unitId: (json['unitId'] as num?)?.toInt() ?? 1,
      outdoorRegister: (json['outdoorRegister'] as num?)?.toInt() ?? 1,
      flowRegister: (json['flowRegister'] as num?)?.toInt() ?? 2,
      returnRegister: (json['returnRegister'] as num?)?.toInt() ?? 3,
      hotWaterRegister: (json['hotWaterRegister'] as num?)?.toInt() ?? 4,
      roomTargetRegister: (json['roomTargetRegister'] as num?)?.toInt(),
      heatingCurveShiftRegister:
          (json['heatingCurveShiftRegister'] as num?)?.toInt(),
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 0.1,
      isHoldingRegister: json['isHoldingRegister'] as bool? ?? true,
      presetId: json['presetId'] as String? ?? 'standard',
      presetName: json['presetName'] as String? ?? 'Standard Modbus Heizung',
    );
  }

  static Future<GenericModbusConfig> load(FlutterSecureStorage storage) async {
    try {
      final raw = await storage.read(key: storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return GenericModbusConfig.fromJson(decoded);
      }
    } catch (_) {}
    return const GenericModbusConfig();
  }

  Future<void> save(FlutterSecureStorage storage) async {
    try {
      await storage.write(key: storageKey, value: jsonEncode(toJson()));
    } catch (_) {}
  }
}
