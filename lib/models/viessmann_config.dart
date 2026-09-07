import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supported connection mechanisms for Viessmann heating controllers.
enum ViessmannConnectionType {
  /// Local Optolink interface via vcontrold or ESP-Optolink (TCP Socket).
  optolinkTcp,

  /// Official Viessmann ViCare Developer REST API (Cloud).
  vicareRest,
}

/// Preset profile for Viessmann controllers and interfaces.
class ViessmannPreset {
  final String id;
  final String name;
  final String description;
  final ViessmannConnectionType connectionType;
  final int defaultPort;
  final String defaultCircuit;

  const ViessmannPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.connectionType,
    this.defaultPort = 3002,
    this.defaultCircuit = '0',
  });
}

/// Configuration model for Viessmann Vitotronic & ViCare controllers.
///
/// Supports:
/// 1. Local Optolink hardware adapters (vcontrold / ESP-Optolink on port 3002/7362).
/// 2. Viessmann ViCare Cloud REST API (Vitoconnect / ViCare Token).
class ViessmannConfig {
  static const String storageKey = 'viessmann_config';

  final ViessmannConnectionType connectionType;
  final String host;
  final int port;
  final String apiToken;
  final String installationId;
  final String circuit;
  final int timeoutSeconds;
  final int cloudPollingIntervalSeconds;
  final String presetId;
  final String presetName;

  static const List<ViessmannPreset> presets = [
    ViessmannPreset(
      id: 'optolink_vcontrold',
      name: 'Viessmann Optolink (vcontrold / Open3E)',
      description: 'Lokaler vcontrold oder Open3E Daemon über Optolink (Port 3002)',
      connectionType: ViessmannConnectionType.optolinkTcp,
      defaultPort: 3002,
      defaultCircuit: '0',
    ),
    ViessmannPreset(
      id: 'esp_optolink',
      name: 'ESP-Optolink Gateway (WLAN / TCP)',
      description: 'Drahtloser ESP32/ESP8266 Optokopf für Vitotronic im lokalen WLAN',
      connectionType: ViessmannConnectionType.optolinkTcp,
      defaultPort: 3002,
      defaultCircuit: '0',
    ),
    ViessmannPreset(
      id: 'vicare_cloud',
      name: 'Viessmann ViCare Developer API (Cloud REST)',
      description: 'Offizielle Viessmann IoT Cloud-Schnittstelle über Vitoconnect & API-Token (60s Quoten-Schutz)',
      connectionType: ViessmannConnectionType.vicareRest,
      defaultPort: 443,
      defaultCircuit: '0',
    ),
    ViessmannPreset(
      id: 'vitotronic_200',
      name: 'Viessmann Vitotronic 200 (Optolink)',
      description: 'Optimiert für Vitotronic 200 KW2/KO1B/HO1B Regelungen über vcontrold / Open3E',
      connectionType: ViessmannConnectionType.optolinkTcp,
      defaultPort: 3002,
      defaultCircuit: '0',
    ),
    ViessmannPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Individuelle Verbindungsparameter für Viessmann Systeme',
      connectionType: ViessmannConnectionType.optolinkTcp,
      defaultPort: 3002,
      defaultCircuit: '0',
    ),
  ];

  const ViessmannConfig({
    this.connectionType = ViessmannConnectionType.optolinkTcp,
    this.host = '192.168.1.130',
    this.port = 3002,
    this.apiToken = '',
    this.installationId = '',
    this.circuit = '0',
    this.timeoutSeconds = 5,
    this.cloudPollingIntervalSeconds = 60,
    this.presetId = 'optolink_vcontrold',
    this.presetName = 'Viessmann Optolink (vcontrold / Open3E)',
  });

  factory ViessmannConfig.fromPreset(
    ViessmannPreset preset, {
    String host = '192.168.1.130',
    String apiToken = '',
  }) {
    return ViessmannConfig(
      connectionType: preset.connectionType,
      host: host,
      port: preset.defaultPort,
      apiToken: apiToken,
      circuit: preset.defaultCircuit,
      presetId: preset.id,
      presetName: preset.name,
    );
  }

  ViessmannConfig copyWith({
    ViessmannConnectionType? connectionType,
    String? host,
    int? port,
    String? apiToken,
    String? installationId,
    String? circuit,
    int? timeoutSeconds,
    int? cloudPollingIntervalSeconds,
    String? presetId,
    String? presetName,
  }) {
    return ViessmannConfig(
      connectionType: connectionType ?? this.connectionType,
      host: host ?? this.host,
      port: port ?? this.port,
      apiToken: apiToken ?? this.apiToken,
      installationId: installationId ?? this.installationId,
      circuit: circuit ?? this.circuit,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      cloudPollingIntervalSeconds:
          cloudPollingIntervalSeconds ?? this.cloudPollingIntervalSeconds,
      presetId: presetId ?? this.presetId,
      presetName: presetName ?? this.presetName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'connectionType': connectionType.name,
      'host': host,
      'port': port,
      'apiToken': apiToken,
      'installationId': installationId,
      'circuit': circuit,
      'timeoutSeconds': timeoutSeconds,
      'cloudPollingIntervalSeconds': cloudPollingIntervalSeconds,
      'presetId': presetId,
      'presetName': presetName,
    };
  }

  factory ViessmannConfig.fromJson(Map<String, dynamic> json) {
    final connStr = json['connectionType'] as String? ?? 'optolinkTcp';
    final connType = ViessmannConnectionType.values.firstWhere(
      (e) => e.name == connStr,
      orElse: () => ViessmannConnectionType.optolinkTcp,
    );

    return ViessmannConfig(
      connectionType: connType,
      host: json['host'] as String? ?? '192.168.1.130',
      port: (json['port'] as num?)?.toInt() ?? 3002,
      apiToken: json['apiToken'] as String? ?? '',
      installationId: json['installationId'] as String? ?? '',
      circuit: json['circuit'] as String? ?? '0',
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 5,
      cloudPollingIntervalSeconds:
          (json['cloudPollingIntervalSeconds'] as num?)?.toInt() ?? 60,
      presetId: json['presetId'] as String? ?? 'optolink_vcontrold',
      presetName: json['presetName'] as String? ?? 'Viessmann Optolink (vcontrold / Open3E)',
    );
  }

  /// Loads stored config from secure storage, falling back to defaults.
  static Future<ViessmannConfig> load(FlutterSecureStorage storage) async {
    try {
      final raw = await storage.read(key: storageKey);
      if (raw == null || raw.trim().isEmpty) {
        return const ViessmannConfig();
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ViessmannConfig.fromJson(map);
    } catch (_) {
      return const ViessmannConfig();
    }
  }

  /// Persists config into secure storage.
  Future<void> save(FlutterSecureStorage storage) async {
    final raw = jsonEncode(toJson());
    await storage.write(key: storageKey, value: raw);
  }
}
