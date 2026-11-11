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

  /// Client ID of the user's app in the Viessmann developer portal and a
  /// refresh token (scope `offline_access`, valid about 180 days). With both
  /// the driver renews the one-hour access token by itself.
  final String clientId;
  final String refreshToken;
  final String installationId;
  final String circuit;
  final int timeoutSeconds;
  final int cloudPollingIntervalSeconds;
  final String presetId;
  final String presetName;

  static const List<ViessmannPreset> presets = [
    ViessmannPreset(
      id: 'optolink_vcontrold',
      name: 'Viessmann Optolink (vcontrold)',
      description: 'Lokaler vcontrold-Dienst (openv) am Optolink-Adapter, Port 3002, Kommandonamen der mitgelieferten vito.xml',
      connectionType: ViessmannConnectionType.optolinkTcp,
      defaultPort: 3002,
      defaultCircuit: '0',
    ),
    ViessmannPreset(
      id: 'vicare_cloud',
      name: 'Viessmann ViCare API (Cloud)',
      description: 'Viessmann-Cloud über Vitoconnect. Mit Client-ID und Refresh-Token erneuert die App den Zugang selbst.',
      connectionType: ViessmannConnectionType.vicareRest,
      defaultPort: 443,
      defaultCircuit: '0',
    ),
  ];

  /// True when the access token can be renewed without the user.
  bool get canRefreshToken => clientId.trim().isNotEmpty && refreshToken.trim().isNotEmpty;

  const ViessmannConfig({
    this.connectionType = ViessmannConnectionType.optolinkTcp,
    this.host = '192.168.1.130',
    this.port = 3002,
    this.apiToken = '',
    this.clientId = '',
    this.refreshToken = '',
    this.installationId = '',
    this.circuit = '0',
    this.timeoutSeconds = 5,
    this.cloudPollingIntervalSeconds = 60,
    this.presetId = 'optolink_vcontrold',
    this.presetName = 'Viessmann Optolink (vcontrold)',
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
    String? clientId,
    String? refreshToken,
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
      clientId: clientId ?? this.clientId,
      refreshToken: refreshToken ?? this.refreshToken,
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
      'clientId': clientId,
      'refreshToken': refreshToken,
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
      clientId: json['clientId'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      installationId: json['installationId'] as String? ?? '',
      circuit: json['circuit'] as String? ?? '0',
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 5,
      cloudPollingIntervalSeconds:
          (json['cloudPollingIntervalSeconds'] as num?)?.toInt() ?? 60,
      // Only two presets are left (the others were the same connection under
      // names of adapters that do not speak the vcontrold protocol).
      presetId: connType == ViessmannConnectionType.vicareRest ? 'vicare_cloud' : 'optolink_vcontrold',
      presetName: connType == ViessmannConnectionType.vicareRest
          ? 'Viessmann ViCare API (Cloud)'
          : 'Viessmann Optolink (vcontrold)',
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
