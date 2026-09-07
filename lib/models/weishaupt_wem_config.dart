import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Predefined presets for Weishaupt WEM (Weishaupt Energie Management) gateways.
class WeishauptWemPreset {
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

  const WeishauptWemPreset({
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

/// Configuration model for Weishaupt WEM systems communicating via Modbus TCP.
///
/// Supports Weishaupt WWP LS split heat pumps, Biblock WBB, and WTC-GW gas condensing
/// systems with integrated WEM Modbus TCP communication.
class WeishauptWemConfig {
  static const String storageKey = 'weishaupt_wem_config';

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

  static const List<WeishauptWemPreset> presets = [
    WeishauptWemPreset(
      id: 'wem_wwp_split',
      name: 'Weishaupt WWP LS / WWP LB (Split-Wärmepumpe)',
      description: 'Weishaupt WEM Split-Wärmepumpe Modbus TCP (Reg 3101=Außen, 3102=Vorlauf, 3103=Rücklauf, 3104=WW)',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 3101,
      flowRegister: 3102,
      returnRegister: 3103,
      hotWaterRegister: 3104,
      roomTargetRegister: 3105,
      heatingCurveShiftRegister: 3106,
      multiplier: 0.1,
      isHoldingRegister: true,
    ),
    WeishauptWemPreset(
      id: 'wem_wtc_gw',
      name: 'Weishaupt WTC-GW (Gas-Brennwert WEM)',
      description: 'Weishaupt WTC Gas-Brennwertgerät mit WEM-Portal Modbus-Schnittstelle (Reg 1..6)',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 1,
      flowRegister: 2,
      returnRegister: 3,
      hotWaterRegister: 4,
      roomTargetRegister: 5,
      heatingCurveShiftRegister: 6,
      multiplier: 0.1,
      isHoldingRegister: true,
    ),
    WeishauptWemPreset(
      id: 'wem_biblock',
      name: 'Weishaupt BiBlock (WBB Wärmepumpe)',
      description: 'Weishaupt WBB Modbus TCP Standardbelegung (Reg 3101..3106, Faktor 0.1)',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 3101,
      flowRegister: 3102,
      returnRegister: 3103,
      hotWaterRegister: 3104,
      roomTargetRegister: 3105,
      heatingCurveShiftRegister: 3106,
      multiplier: 0.1,
      isHoldingRegister: true,
    ),
    WeishauptWemPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Individuelle Registeradressen und Modbus-Parameter für Weishaupt',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 3101,
      flowRegister: 3102,
      returnRegister: 3103,
      hotWaterRegister: 3104,
      roomTargetRegister: 3105,
      heatingCurveShiftRegister: 3106,
      multiplier: 0.1,
      isHoldingRegister: true,
    ),
  ];

  const WeishauptWemConfig({
    this.host = '192.168.1.150',
    this.port = 502,
    this.unitId = 1,
    this.outdoorRegister = 3101,
    this.flowRegister = 3102,
    this.returnRegister = 3103,
    this.hotWaterRegister = 3104,
    this.roomTargetRegister = 3105,
    this.heatingCurveShiftRegister = 3106,
    this.multiplier = 0.1,
    this.isHoldingRegister = true,
    this.presetId = 'wem_wwp_split',
    this.presetName = 'Weishaupt WWP LS / WWP LB (Split-Wärmepumpe)',
  });

  factory WeishauptWemConfig.fromPreset(
    WeishauptWemPreset preset, {
    String host = '192.168.1.150',
  }) {
    return WeishauptWemConfig(
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

  WeishauptWemConfig copyWith({
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
    return WeishauptWemConfig(
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

  factory WeishauptWemConfig.fromJson(Map<String, dynamic> json) {
    return WeishauptWemConfig(
      host: json['host'] as String? ?? '192.168.1.150',
      port: (json['port'] as num?)?.toInt() ?? 502,
      unitId: (json['unitId'] as num?)?.toInt() ?? 1,
      outdoorRegister: (json['outdoorRegister'] as num?)?.toInt() ?? 3101,
      flowRegister: (json['flowRegister'] as num?)?.toInt() ?? 3102,
      returnRegister: (json['returnRegister'] as num?)?.toInt() ?? 3103,
      hotWaterRegister: (json['hotWaterRegister'] as num?)?.toInt() ?? 3104,
      roomTargetRegister: (json['roomTargetRegister'] as num?)?.toInt() ?? 3105,
      heatingCurveShiftRegister:
          (json['heatingCurveShiftRegister'] as num?)?.toInt() ?? 3106,
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 0.1,
      isHoldingRegister: json['isHoldingRegister'] as bool? ?? true,
      presetId: json['presetId'] as String? ?? 'wem_wwp_split',
      presetName: json['presetName'] as String? ??
          'Weishaupt WWP LS / WWP LB (Split-Wärmepumpe)',
    );
  }

  static Future<WeishauptWemConfig> load(FlutterSecureStorage storage) async {
    try {
      final raw = await storage.read(key: storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return WeishauptWemConfig.fromJson(decoded);
      }
    } catch (_) {}
    return const WeishauptWemConfig();
  }

  Future<void> save(FlutterSecureStorage storage) async {
    try {
      await storage.write(key: storageKey, value: jsonEncode(toJson()));
    } catch (_) {}
  }
}
