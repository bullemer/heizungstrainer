import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preset definition for Bosch / Buderus EMS-ESP gateways.
class BoschBuderusEmsPreset {
  final String id;
  final String name;
  final String description;
  final int defaultPort;
  final String defaultCircuit;
  final bool defaultUseHttps;

  const BoschBuderusEmsPreset({
    required this.id,
    required this.name,
    required this.description,
    this.defaultPort = 80,
    this.defaultCircuit = 'hc1',
    this.defaultUseHttps = false,
  });
}

/// Configuration model for Bosch / Buderus EMS-ESP (Local REST API).
///
/// Supports EMS-ESP v2 and v3 gateways (e.g. BBQKees Gateway-E32/S3, Buderus Logamatic,
/// Bosch Condens, Junkers Cerapur with EMS-Bus).
class BoschBuderusEmsConfig {
  static const String storageKey = 'bosch_buderus_ems_config';

  final String host;
  final int port;
  final String apiToken;
  final String circuit;
  final bool useHttps;
  final int timeoutSeconds;
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
    ),
    BoschBuderusEmsPreset(
      id: 'bbqkees',
      name: 'BBQKees Gateway-E32 / S3',
      description: 'Vorkonfiguriertes BBQKees Gateway für Buderus, Bosch & Junkers EMS-Bus',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
    ),
    BoschBuderusEmsPreset(
      id: 'buderus_logamatic',
      name: 'Buderus Logamatic (RC300 / RC310)',
      description: 'Buderus EMS Plus Regelung mit RC300, RC310 oder BC10/BC25 Basis',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
    ),
    BoschBuderusEmsPreset(
      id: 'bosch_junkers',
      name: 'Bosch Condens / Junkers Heatronic',
      description: 'Junkers / Bosch Brennwertgeräte (Cerapur, Condens 5000/7000) mit EMS',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
    ),
    BoschBuderusEmsPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Individuelle IP-, Port-, Token- und Heizkreis-Konfiguration',
      defaultPort: 80,
      defaultCircuit: 'hc1',
      defaultUseHttps: false,
    ),
  ];

  const BoschBuderusEmsConfig({
    this.host = '192.168.1.120',
    this.port = 80,
    this.apiToken = '',
    this.circuit = 'hc1',
    this.useHttps = false,
    this.timeoutSeconds = 5,
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
      presetId: preset.id,
      presetName: preset.name,
    );
  }

  /// Full base URL for the EMS-ESP gateway.
  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  /// Constructs a URI for the gateway endpoint.
  Uri getUri(String endpoint) {
    final normalized = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$baseUrl$normalized');
  }

  BoschBuderusEmsConfig copyWith({
    String? host,
    int? port,
    String? apiToken,
    String? circuit,
    bool? useHttps,
    int? timeoutSeconds,
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
      'presetId': presetId,
      'presetName': presetName,
    };
  }

  factory BoschBuderusEmsConfig.fromJson(Map<String, dynamic> json) {
    return BoschBuderusEmsConfig(
      host: json['host'] as String? ?? '192.168.1.120',
      port: (json['port'] as num?)?.toInt() ?? 80,
      apiToken: json['apiToken'] as String? ?? '',
      circuit: json['circuit'] as String? ?? 'hc1',
      useHttps: json['useHttps'] as bool? ?? false,
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 5,
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
