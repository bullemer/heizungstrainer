import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:modbus_client/modbus_client.dart';

/// Supported byte/word ordering (endianness) for Modbus registers.
enum ModbusWordOrder {
  /// Standard Big-Endian (High Byte / High Word first, ABCD).
  bigEndian,

  /// Little-Endian (Low Byte / Low Word first, DCBA).
  littleEndian,

  /// Mid-Big-Endian / Word Swap (CDAB) - commonly used in Luxtronik and Siemens controllers.
  wordSwap,

  /// Mid-Little-Endian / Byte Swap (BADC).
  byteSwap,
}

extension ModbusWordOrderExtension on ModbusWordOrder {
  ModbusEndianness get toModbusEndianness {
    switch (this) {
      case ModbusWordOrder.bigEndian:
        return ModbusEndianness.ABCD;
      case ModbusWordOrder.littleEndian:
        return ModbusEndianness.DCBA;
      case ModbusWordOrder.wordSwap:
        return ModbusEndianness.CDAB;
      case ModbusWordOrder.byteSwap:
        return ModbusEndianness.BADC;
    }
  }

  String get displayName {
    switch (this) {
      case ModbusWordOrder.bigEndian:
        return 'Big-Endian (ABCD - Standard)';
      case ModbusWordOrder.littleEndian:
        return 'Little-Endian (DCBA)';
      case ModbusWordOrder.wordSwap:
        return 'Word-Swap (CDAB - Luxtronik/Siemens)';
      case ModbusWordOrder.byteSwap:
        return 'Byte-Swap (BADC)';
    }
  }
}

/// Supported register data types.
enum ModbusRegisterDataType {
  /// 16-Bit signed integer (most heating controllers).
  int16,

  /// 16-Bit unsigned integer.
  uint16,

  /// 32-Bit signed integer spanning 2 consecutive 16-bit registers.
  int32,

  /// 32-Bit unsigned integer spanning 2 consecutive 16-bit registers.
  uint32,

  /// 32-Bit IEEE 754 floating-point number spanning 2 consecutive 16-bit registers.
  float32,
}

extension ModbusRegisterDataTypeExtension on ModbusRegisterDataType {
  String get displayName {
    switch (this) {
      case ModbusRegisterDataType.int16:
        return '16-Bit Vorzeichenbehaftet (int16)';
      case ModbusRegisterDataType.uint16:
        return '16-Bit Vorzeichenlos (uint16)';
      case ModbusRegisterDataType.int32:
        return '32-Bit Vorzeichenbehaftet (int32)';
      case ModbusRegisterDataType.uint32:
        return '32-Bit Vorzeichenlos (uint32)';
      case ModbusRegisterDataType.float32:
        return '32-Bit Fließkommazahl (float32)';
    }
  }
}

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
  final ModbusWordOrder wordOrder;
  final ModbusRegisterDataType dataType;
  final int pollingIntervalSeconds;

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
    this.wordOrder = ModbusWordOrder.bigEndian,
    this.dataType = ModbusRegisterDataType.int16,
    this.pollingIntervalSeconds = 10,
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
  final ModbusWordOrder wordOrder;
  final ModbusRegisterDataType dataType;
  final int pollingIntervalSeconds;
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
      wordOrder: ModbusWordOrder.bigEndian,
      dataType: ModbusRegisterDataType.int16,
      pollingIntervalSeconds: 10,
    ),
    GenericModbusPreset(
      id: 'stiebel_isg',
      name: 'Stiebel Eltron (ISG Modbus)',
      description: 'ISG Web Modbus TCP (501=Außen, 502=Vorlauf HK1, 503=Rücklauf, 504=Warmwasser, 1501=Raum-Soll HK1, 1502=Soll HK2), 5s Polling-Drosselung',
      outdoorRegister: 501,
      flowRegister: 502,
      returnRegister: 503,
      hotWaterRegister: 504,
      roomTargetRegister: 1501,
      heatingCurveShiftRegister: 1502,
      multiplier: 0.1,
      isHoldingRegister: true,
      wordOrder: ModbusWordOrder.bigEndian,
      dataType: ModbusRegisterDataType.int16,
      pollingIntervalSeconds: 5,
    ),
    GenericModbusPreset(
      id: 'luxtronik',
      name: 'Luxtronik 2.0 / 2.1 (Alpha Innotec / Novelan)',
      description: 'Luxtronik Wärmepumpenregelung über Modbus TCP (32-Bit / Word-Swap CDAB)',
      outdoorRegister: 100,
      flowRegister: 101,
      returnRegister: 102,
      hotWaterRegister: 103,
      roomTargetRegister: 105,
      heatingCurveShiftRegister: 106,
      multiplier: 0.1,
      isHoldingRegister: true,
      wordOrder: ModbusWordOrder.wordSwap,
      dataType: ModbusRegisterDataType.int32,
      pollingIntervalSeconds: 10,
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
      wordOrder: ModbusWordOrder.bigEndian,
      dataType: ModbusRegisterDataType.int16,
      pollingIntervalSeconds: 10,
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
      wordOrder: ModbusWordOrder.bigEndian,
      dataType: ModbusRegisterDataType.int16,
      pollingIntervalSeconds: 10,
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
      wordOrder: ModbusWordOrder.bigEndian,
      dataType: ModbusRegisterDataType.int16,
      pollingIntervalSeconds: 10,
    ),
    GenericModbusPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Vollständig freie Konfiguration aller Register, Datentypen und Wort-Reihenfolgen',
      outdoorRegister: 1,
      flowRegister: 2,
      returnRegister: 3,
      hotWaterRegister: 4,
      roomTargetRegister: 5,
      heatingCurveShiftRegister: 6,
      multiplier: 0.1,
      wordOrder: ModbusWordOrder.bigEndian,
      dataType: ModbusRegisterDataType.int16,
      pollingIntervalSeconds: 10,
    ),
    // Samson TROVIS 5573/5576/5578/5579/5578-E – register list from the
    // manufacturer-format export "5578 rev 2.62" (github.com/Tom-Bom-badil/
    // samson_trovis_557x) and the trovis-modbus library; NOT verified on
    // hardware. Holding registers 4xxxx → protocol address HR − 40001, int16
    // ×0.1: AF1 40010, VF1 40013, RüF1 40017, SF1 40023. Read-only on purpose:
    // writes need the write-enable key in HR 40145 (default 1732, 30 min).
    // 5578-E: Modbus TCP built in; others via SAM HOME/LAN/MOBILE gateway or an
    // RS-485→TCP converter. Factory station address 255 (set on the controller).
    GenericModbusPreset(
      id: 'samson_trovis',
      name: 'Samson TROVIS 557x (Fernwärme/Kessel)',
      description: 'TROVIS 5573/5576/5578/5579/5578-E: AF1=Außen, VF1=Vorlauf, RüF1=Rücklauf, SF1=Speicher (nur lesen; '
          '5578-E direkt per Modbus TCP, andere über SAM-Gateway/RS-485-Wandler; Stationsadresse ab Werk 255)',
      defaultUnitId: 255,
      outdoorRegister: 9,
      flowRegister: 12,
      returnRegister: 16,
      hotWaterRegister: 22,
      multiplier: 0.1,
      isHoldingRegister: true,
      wordOrder: ModbusWordOrder.bigEndian,
      dataType: ModbusRegisterDataType.int16,
      pollingIntervalSeconds: 15,
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
    this.wordOrder = ModbusWordOrder.bigEndian,
    this.dataType = ModbusRegisterDataType.int16,
    this.pollingIntervalSeconds = 10,
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
      wordOrder: preset.wordOrder,
      dataType: preset.dataType,
      pollingIntervalSeconds: preset.pollingIntervalSeconds,
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
    ModbusWordOrder? wordOrder,
    ModbusRegisterDataType? dataType,
    int? pollingIntervalSeconds,
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
      wordOrder: wordOrder ?? this.wordOrder,
      dataType: dataType ?? this.dataType,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
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
        'wordOrder': wordOrder.name,
        'dataType': dataType.name,
        'pollingIntervalSeconds': pollingIntervalSeconds,
        'presetId': presetId,
        'presetName': presetName,
      };

  factory GenericModbusConfig.fromJson(Map<String, dynamic> json) {
    final wordOrderStr = json['wordOrder'] as String?;
    final wordOrder = ModbusWordOrder.values.firstWhere(
      (e) => e.name == wordOrderStr,
      orElse: () => ModbusWordOrder.bigEndian,
    );

    final dataTypeStr = json['dataType'] as String?;
    final dataType = ModbusRegisterDataType.values.firstWhere(
      (e) => e.name == dataTypeStr,
      orElse: () => ModbusRegisterDataType.int16,
    );

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
      wordOrder: wordOrder,
      dataType: dataType,
      pollingIntervalSeconds: (json['pollingIntervalSeconds'] as num?)?.toInt() ?? 10,
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
