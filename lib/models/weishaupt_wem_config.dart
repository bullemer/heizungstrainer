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

  // Register map of the Weishaupt heat pumps with built-in Modbus TCP, taken
  // from the open-source Home Assistant integration OStrama/weishaupt_modbus
  // (no manufacturer list found; NOT verified on hardware). The full 5-digit
  // number is the protocol address. Sensors are INPUT registers (FC04, ÷10):
  // 30001 outdoor, 31105 heating circuit flow, 33105 heat pump return,
  // 32102 hot water. Room setpoint "Komfort" = holding 41105 (÷10).
  // There is no parallel-shift register. Up to 1.2.10 the app shipped an
  // invented map (holding 3101–3106) that cannot have worked.
  //
  // WTC gas boilers have no Modbus of their own; the separate "Gateway
  // WEM-Modbus" uses a completely different map (manual 83325901) that is not
  // implemented – use "Benutzerdefiniert" for it.
  static const List<WeishauptWemPreset> presets = [
    WeishauptWemPreset(
      id: 'wem_wwp_split',
      name: 'Weishaupt Wärmepumpe (WWP / Biblock, Modbus TCP)',
      description: 'Eingangsregister 30001=Außen, 31105=Vorlauf Heizkreis, 33105=Rücklauf, 32102=Warmwasser; '
          'Raum-Soll Komfort = Halteregister 41105. Keine Parallelverschiebung per Modbus.',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 30001,
      flowRegister: 31105,
      returnRegister: 33105,
      hotWaterRegister: 32102,
      roomTargetRegister: 41105,
      heatingCurveShiftRegister: null,
      multiplier: 0.1,
      isHoldingRegister: false,
    ),
    WeishauptWemPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Eigene Registeradressen, z. B. für das Gateway WEM-Modbus (WTC-Gasgeräte)',
      defaultPort: 502,
      defaultUnitId: 1,
      outdoorRegister: 30001,
      flowRegister: 31105,
      returnRegister: 33105,
      hotWaterRegister: 32102,
      roomTargetRegister: null,
      heatingCurveShiftRegister: null,
      multiplier: 0.1,
      isHoldingRegister: false,
    ),
  ];

  const WeishauptWemConfig({
    this.host = '192.168.1.150',
    this.port = 502,
    this.unitId = 1,
    this.outdoorRegister = 30001,
    this.flowRegister = 31105,
    this.returnRegister = 33105,
    this.hotWaterRegister = 32102,
    this.roomTargetRegister = 41105,
    this.heatingCurveShiftRegister,
    this.multiplier = 0.1,
    this.isHoldingRegister = false,
    this.presetId = 'wem_wwp_split',
    this.presetName = 'Weishaupt Wärmepumpe (WWP / Biblock, Modbus TCP)',
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

  static int? _optionalRegister(Map<String, dynamic> json, String key) =>
      (json[key] as num?)?.toInt();

  factory WeishauptWemConfig.fromJson(Map<String, dynamic> json) {
    final presetId = json['presetId'] as String? ?? 'wem_wwp_split';
    final outdoor = (json['outdoorRegister'] as num?)?.toInt();
    // <= 1.2.10: invented maps (heat pump 3101–3106, "WTC-GW" 1–6). Heat pump
    // configs move to the real map; the WTC preset no longer exists and
    // becomes a read-only custom config the user has to fill in.
    if ((presetId == 'wem_wwp_split' || presetId == 'wem_biblock') && (outdoor == null || outdoor == 3101)) {
      return WeishauptWemConfig(
        host: json['host'] as String? ?? '192.168.1.150',
        port: (json['port'] as num?)?.toInt() ?? 502,
        unitId: (json['unitId'] as num?)?.toInt() ?? 1,
      );
    }
    final legacy = presetId == 'wem_wtc_gw' || presetId == 'wem_biblock';
    return WeishauptWemConfig(
      host: json['host'] as String? ?? '192.168.1.150',
      port: (json['port'] as num?)?.toInt() ?? 502,
      unitId: (json['unitId'] as num?)?.toInt() ?? 1,
      outdoorRegister: outdoor ?? 30001,
      flowRegister: (json['flowRegister'] as num?)?.toInt() ?? 31105,
      returnRegister: (json['returnRegister'] as num?)?.toInt() ?? 33105,
      hotWaterRegister: (json['hotWaterRegister'] as num?)?.toInt() ?? 32102,
      roomTargetRegister: legacy ? null : _optionalRegister(json, 'roomTargetRegister'),
      heatingCurveShiftRegister: legacy ? null : _optionalRegister(json, 'heatingCurveShiftRegister'),
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 0.1,
      isHoldingRegister: json['isHoldingRegister'] as bool? ?? false,
      presetId: legacy ? 'custom' : presetId,
      presetName: legacy ? 'Benutzerdefiniert' : (json['presetName'] as String? ?? 'Benutzerdefiniert'),
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
