import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Predefined presets for Vaillant heating systems using an eBUSd gateway.
class VaillantEbusdPreset {
  final String id;
  final String name;
  final String description;
  final int defaultPort;
  final String defaultCircuit;
  final bool defaultUseHttps;

  const VaillantEbusdPreset({
    required this.id,
    required this.name,
    required this.description,
    this.defaultPort = 8889,
    this.defaultCircuit = 'bai',
    this.defaultUseHttps = false,
  });
}

/// Configuration model for Vaillant systems connected via eBUSd (HTTP REST JSON API).
///
/// Supports eBUSd gateways (e.g. ebusd on Raspberry Pi, ESP32 eBUS Adapter, ebusd-esp)
/// querying the standard JSON API endpoint (`http://<host>:8889/data`).
class VaillantEbusdConfig {
  static const String storageKey = 'vaillant_ebusd_config';

  final String host;
  final int port;
  final String circuit;
  final String apiToken;
  final bool useHttps;
  final int timeoutSeconds;
  final String presetId;
  final String presetName;

  static const List<VaillantEbusdPreset> presets = [
    VaillantEbusdPreset(
      id: 'ebusd_http_json',
      name: 'eBUSd HTTP JSON API (Standard)',
      description: 'Standard eBUSd HTTP JSON Daemon (Port 8889, endpoint /data, circuit bai)',
      defaultPort: 8889,
      defaultCircuit: 'bai',
      defaultUseHttps: false,
    ),
    VaillantEbusdPreset(
      id: 'ebusd_sensocomfort',
      name: 'Vaillant sensoCOMFORT (VRC 720)',
      description: 'sensoCOMFORT Systemregler via eBUSd (Heizkreis 720 / bai)',
      defaultPort: 8889,
      defaultCircuit: '720',
      defaultUseHttps: false,
    ),
    VaillantEbusdPreset(
      id: 'ebusd_multimatic',
      name: 'Vaillant multiMATIC (VRC 700)',
      description: 'multiMATIC 700 Regelung via eBUSd (Heizkreis 700 / bai)',
      defaultPort: 8889,
      defaultCircuit: '700',
      defaultUseHttps: false,
    ),
    VaillantEbusdPreset(
      id: 'ebusd_calormatic',
      name: 'Vaillant calorMATIC (VRC 470 / 430)',
      description: 'calorMATIC Witterungsführung via eBUSd (Heizkreis 470 / bai)',
      defaultPort: 8889,
      defaultCircuit: '470',
      defaultUseHttps: false,
    ),
    VaillantEbusdPreset(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Individuelle eBUSd IP-Adresse, Port und Heizkreis-Bezeichnung',
      defaultPort: 8889,
      defaultCircuit: 'bai',
      defaultUseHttps: false,
    ),
  ];

  const VaillantEbusdConfig({
    this.host = '192.168.1.140',
    this.port = 8889,
    this.circuit = 'bai',
    this.apiToken = '',
    this.useHttps = false,
    this.timeoutSeconds = 5,
    this.presetId = 'ebusd_http_json',
    this.presetName = 'eBUSd HTTP JSON API (Standard)',
  });

  factory VaillantEbusdConfig.fromPreset(
    VaillantEbusdPreset preset, {
    String host = '192.168.1.140',
    String apiToken = '',
  }) {
    return VaillantEbusdConfig(
      host: host,
      port: preset.defaultPort,
      circuit: preset.defaultCircuit,
      apiToken: apiToken,
      useHttps: preset.defaultUseHttps,
      presetId: preset.id,
      presetName: preset.name,
    );
  }

  /// Full base URL for the eBUSd HTTP endpoint.
  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  /// Constructs a URI for the gateway endpoint.
  Uri getUri(String endpoint) {
    final normalized = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$baseUrl$normalized');
  }

  VaillantEbusdConfig copyWith({
    String? host,
    int? port,
    String? circuit,
    String? apiToken,
    bool? useHttps,
    int? timeoutSeconds,
    String? presetId,
    String? presetName,
  }) {
    return VaillantEbusdConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      circuit: circuit ?? this.circuit,
      apiToken: apiToken ?? this.apiToken,
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
      'circuit': circuit,
      'apiToken': apiToken,
      'useHttps': useHttps,
      'timeoutSeconds': timeoutSeconds,
      'presetId': presetId,
      'presetName': presetName,
    };
  }

  factory VaillantEbusdConfig.fromJson(Map<String, dynamic> json) {
    return VaillantEbusdConfig(
      host: json['host'] as String? ?? '192.168.1.140',
      port: (json['port'] as num?)?.toInt() ?? 8889,
      circuit: json['circuit'] as String? ?? 'bai',
      apiToken: json['apiToken'] as String? ?? '',
      useHttps: json['useHttps'] as bool? ?? false,
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 5,
      presetId: json['presetId'] as String? ?? 'ebusd_http_json',
      presetName: json['presetName'] as String? ?? 'eBUSd HTTP JSON API (Standard)',
    );
  }

  /// Loads stored config from secure storage, falling back to defaults.
  static Future<VaillantEbusdConfig> load(FlutterSecureStorage storage) async {
    try {
      final raw = await storage.read(key: storageKey);
      if (raw == null || raw.trim().isEmpty) {
        return const VaillantEbusdConfig();
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return VaillantEbusdConfig.fromJson(map);
    } catch (_) {
      return const VaillantEbusdConfig();
    }
  }

  /// Persists config into secure storage.
  Future<void> save(FlutterSecureStorage storage) async {
    final raw = jsonEncode(toJson());
    await storage.write(key: storageKey, value: raw);
  }
}
