import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Communication protocol mode for Bosch / Buderus controllers.
enum BoschGatewayType {
  /// EMS-ESP REST API (BBQKees Gateway-E32/S3, open JSON API).
  emsEsp,

  /// Bosch / Buderus KM200 / MB LAN 2 / MX300 (Local AES-128-ECB encrypted REST API).
  km200,
}

extension BoschGatewayTypeExtension on BoschGatewayType {
  String get displayName {
    switch (this) {
      case BoschGatewayType.emsEsp:
        return 'EMS-ESP REST API (BBQKees / ESP32)';
      case BoschGatewayType.km200:
        return 'Bosch/Buderus KM200 / MB LAN (AES-128)';
    }
  }
}

/// Preset definition for Bosch / Buderus EMS-ESP and KM200 gateways.
class BoschBuderusEmsPreset {
  final String id;
  final String name;
  final String description;
  final int defaultPort;
  final String defaultCircuit;
  final bool defaultUseHttps;
  final BoschGatewayType defaultGatewayType;

  const BoschBuderusEmsPreset({
    required this.id,
    required this.name,
    required this.description,
    this.defaultPort = 80,
    this.defaultCircuit = 'hc1',
    this.defaultUseHttps = false,
    this.defaultGatewayType = BoschGatewayType.emsEsp,
  });
}

/// Configuration model for Bosch / Buderus EMS (Local REST API & KM200 AES-128).
///
/// Supports:
/// 1. EMS-ESP v2 and v3 gateways (e.g. BBQKees Gateway-E32/S3, Buderus Logamatic,
///    Bosch Condens, Junkers Cerapur with EMS-Bus).
/// 2. Official Bosch / Buderus KM200, MB LAN 2, and MX300 gateways with local
///    hardware AES-128-ECB encryption.
class BoschBuderusEmsConfig {
  static const String storageKey = 'bosch_buderus_ems_config';

  static final List<int> _km200Salt1 = [
    0x86, 0x78, 0x45, 0xcd, 0x72, 0x27, 0x2a, 0x93,
    0x58, 0x47, 0x3d, 0x3d, 0x99, 0x26, 0xb8, 0xb6,
  ];
  static final List<int> _km200Salt2 = [
    0x30, 0x78, 0x30, 0x62, 0x61, 0x32, 0x34, 0x37,
    0x35, 0x33, 0x34, 0x39, 0x64, 0x32, 0x30, 0x61,
  ];

  final String host;
  final int port;
  final String apiToken;
  final String circuit;
  final bool useHttps;
  final int timeoutSeconds;
  final BoschGatewayType gatewayType;
  final String gatewayPassword;
  final String privatePassword;
  final String km200Key;
  final String presetId;
  final String presetName;

  static const List<BoschBuderusEmsPreset> presets = [
    BoschBuderusEmsPreset(
      id: 'standard',
      name: 'EMS-ESP Gateway (Standard)',
      description: 'Standard EMS-ESP v3 REST-Schnittstelle über LAN/WLAN (Port 80, hc1)',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
      defaultGatewayType: BoschGatewayType.emsEsp,
    ),
    BoschBuderusEmsPreset(
      id: 'bbqkees',
      name: 'BBQKees Gateway-E32 / S3',
      description: 'Vorkonfiguriertes BBQKees Gateway für Buderus, Bosch & Junkers EMS-Bus',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
      defaultGatewayType: BoschGatewayType.emsEsp,
    ),
    BoschBuderusEmsPreset(
      id: 'km200_mblan',
      name: 'Buderus KM200 / MB LAN (AES-128)',
      description: 'Offizielles Bosch/Buderus LAN-Gateway mit lokaler AES-128-ECB Verschlüsselung (Port 80)',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
      defaultGatewayType: BoschGatewayType.km200,
    ),
    BoschBuderusEmsPreset(
      id: 'buderus_logamatic',
      name: 'Buderus Logamatic (RC300 / RC310)',
      description: 'Buderus EMS Plus Regelung mit RC300, RC310 oder BC10/BC25 Basis',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
      defaultGatewayType: BoschGatewayType.emsEsp,
    ),
    BoschBuderusEmsPreset(
      id: 'bosch_junkers',
      name: 'Bosch Condens / Junkers Heatronic',
      description: 'Junkers / Bosch Brennwertgeräte (Cerapur, Condens 5000/7000) mit EMS',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
      defaultGatewayType: BoschGatewayType.emsEsp,
    ),
    BoschBuderusEmsPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Individuelle IP-, Port-, Token- und Gateway-Typ Konfiguration',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
      defaultGatewayType: BoschGatewayType.emsEsp,
    ),
  ];

  const BoschBuderusEmsConfig({
    this.host = '192.168.1.120',
    this.port = 80,
    this.apiToken = '',
    this.circuit = 'hc1',
    this.useHttps = false,
    this.timeoutSeconds = 5,
    this.gatewayType = BoschGatewayType.emsEsp,
    this.gatewayPassword = '',
    this.privatePassword = '',
    this.km200Key = '',
    this.presetId = 'standard',
    this.presetName = 'EMS-ESP Gateway (Standard)',
  });

  factory BoschBuderusEmsConfig.fromPreset(
    BoschBuderusEmsPreset preset, {
    String host = '192.168.1.120',
    String apiToken = '',
  }) {
    return BoschBuderusEmsConfig(
      host: host,
      port: preset.defaultPort,
      apiToken: apiToken,
      circuit: preset.defaultCircuit,
      useHttps: preset.defaultUseHttps,
      gatewayType: preset.defaultGatewayType,
      presetId: preset.id,
      presetName: preset.name,
    );
  }

  /// Full base URL for the EMS-ESP or KM200 gateway.
  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  /// Constructs a URI for the gateway endpoint.
  Uri getUri(String endpoint) {
    final normalized = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$baseUrl$normalized');
  }

  /// Computes or parses the 16-byte AES-128 key for KM200 communication.
  Uint8List? getKm200KeyBytes() {
    if (km200Key.trim().isNotEmpty) {
      final clean = km200Key.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (clean.length == 32) {
        final bytes = Uint8List(16);
        for (int i = 0; i < 16; i++) {
          bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
        }
        return bytes;
      }
    }

    if (gatewayPassword.trim().isNotEmpty && privatePassword.trim().isNotEmpty) {
      final cleanGw = gatewayPassword.replaceAll('-', '').trim();
      final gwBytes = utf8.encode(cleanGw);
      final privBytes = utf8.encode(privatePassword.trim());

      final md5Gw = md5.convert([...gwBytes, ..._km200Salt1]).bytes;
      final md5Priv = md5.convert([..._km200Salt2, ...privBytes]).bytes;

      final key = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        key[i] = md5Gw[i] ^ md5Priv[i];
      }
      return key;
    }

    return null;
  }

  BoschBuderusEmsConfig copyWith({
    String? host,
    int? port,
    String? apiToken,
    String? circuit,
    bool? useHttps,
    int? timeoutSeconds,
    BoschGatewayType? gatewayType,
    String? gatewayPassword,
    String? privatePassword,
    String? km200Key,
    String? presetId,
    String? presetName,
  }) {
    return BoschBuderusEmsConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      apiToken: apiToken ?? this.apiToken,
      circuit: circuit ?? this.circuit,
      useHttps: useHttps ?? this.useHttps,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      gatewayType: gatewayType ?? this.gatewayType,
      gatewayPassword: gatewayPassword ?? this.gatewayPassword,
      privatePassword: privatePassword ?? this.privatePassword,
      km200Key: km200Key ?? this.km200Key,
      presetId: presetId ?? this.presetId,
      presetName: presetName ?? this.presetName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'apiToken': apiToken,
      'circuit': circuit,
      'useHttps': useHttps,
      'timeoutSeconds': timeoutSeconds,
      'gatewayType': gatewayType.name,
      'gatewayPassword': gatewayPassword,
      'privatePassword': privatePassword,
      'km200Key': km200Key,
      'presetId': presetId,
      'presetName': presetName,
    };
  }

  factory BoschBuderusEmsConfig.fromJson(Map<String, dynamic> json) {
    final typeStr = json['gatewayType'] as String?;
    final gatewayType = BoschGatewayType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => BoschGatewayType.emsEsp,
    );

    return BoschBuderusEmsConfig(
      host: json['host'] as String? ?? '192.168.1.120',
      port: (json['port'] as num?)?.toInt() ?? 80,
      apiToken: json['apiToken'] as String? ?? '',
      circuit: json['circuit'] as String? ?? 'hc1',
      useHttps: json['useHttps'] as bool? ?? false,
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 5,
      gatewayType: gatewayType,
      gatewayPassword: json['gatewayPassword'] as String? ?? '',
      privatePassword: json['privatePassword'] as String? ?? '',
      km200Key: json['km200Key'] as String? ?? '',
      presetId: json['presetId'] as String? ?? 'standard',
      presetName: json['presetName'] as String? ?? 'EMS-ESP Gateway (Standard)',
    );
  }

  /// Loads stored config from secure storage, falling back to defaults.
  static Future<BoschBuderusEmsConfig> load(FlutterSecureStorage storage) async {
    try {
      final raw = await storage.read(key: storageKey);
      if (raw == null || raw.trim().isEmpty) {
        return const BoschBuderusEmsConfig();
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return BoschBuderusEmsConfig.fromJson(map);
    } catch (_) {
      return const BoschBuderusEmsConfig();
    }
  }

  /// Persists config into secure storage.
  Future<void> save(FlutterSecureStorage storage) async {
    final raw = jsonEncode(toJson());
    await storage.write(key: storageKey, value: raw);
  }
}

