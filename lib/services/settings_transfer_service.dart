import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:heizungstrainer/billing/billing_storage_keys.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';
import 'package:heizungstrainer/services/curve_optimizer_service.dart';
import 'package:heizungstrainer/services/device_registry.dart';
import 'package:heizungstrainer/services/energy_price_service.dart';

/// Result of [SettingsTransferService.importJson].
class SettingsImportResult {
  const SettingsImportResult({required this.imported, required this.ignored});

  /// Storage keys written.
  final List<String> imported;

  /// Keys in the file that are not importable (unknown or excluded).
  final List<String> ignored;
}

/// Thrown when a file is not a Heizungstrainer settings export.
class SettingsFormatException implements Exception {
  const SettingsFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Exports the app's settings to a JSON file and imports them again – e.g.
/// when switching from the website APK to the Play version (which requires
/// an uninstall and so wipes all app data).
///
/// Never exported: passwords, usernames, API tokens, licence and
/// early-adopter records, review counters, and the per-controller Beta write
/// consent (the user has to confirm that again on the new install).
class SettingsTransferService {
  SettingsTransferService({
    FlutterSecureStorage? storage,
    Map<String, String>? inMemoryStorage,
  })  : _memory = inMemoryStorage,
        _storage = inMemoryStorage != null ? null : (storage ?? const FlutterSecureStorage());

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;

  static const String format = 'heizungstrainer-settings';
  static const int formatVersion = 1;

  /// Plain values copied as they are.
  static const List<String> _plainKeys = [
    'selected_controller_id',
    'auto_connect_controller_id',
    'ecl_controller_ip',
    'selected_billing_id',
    'building_reference',
    'annual_heating_kwh',
    EnergyPriceService.storageKeyPrice,
    EnergyPriceService.storageKeyCarrierId,
    EnergyPriceService.storageKeyIsCustom,
    CurveOptimizerService.storageKey,
  ];

  /// JSON lists of objects with an `id`; merged with what is already there.
  static const List<String> _listKeys = [
    'ecl_controller_backups',
    'ecl_holiday_plans',
  ];

  /// Controller configs (JSON objects); secret fields are stripped on export
  /// and kept from the existing config on import.
  static const List<String> _configKeys = [
    GenericModbusConfig.storageKey,
    BoschBuderusEmsConfig.storageKey,
    ViessmannConfig.storageKey,
    VaillantEbusdConfig.storageKey,
    WeishauptWemConfig.storageKey,
    NibeModbusConfig.storageKey,
  ];

  /// Per billing provider: portal URL and price, never the login.
  static List<String> get _billingKeys => [
        for (final p in DeviceRegistry.knownBillingProviders) ...[
          BillingStorageKeys.portalUrl(p.id),
          BillingStorageKeys.pricePerKwh(p.id),
        ],
      ];

  static List<String> get allowedKeys =>
      [..._plainKeys, ..._listKeys, ..._configKeys, ..._billingKeys];

  static final RegExp _secretField = RegExp(r'token|password|secret|pin', caseSensitive: false);

  Future<String?> _read(String key) async =>
      _memory != null ? _memory[key] : await _storage!.read(key: key);

  Future<void> _write(String key, String value) async {
    if (_memory != null) {
      _memory[key] = value;
    } else {
      await _storage!.write(key: key, value: value);
    }
  }

  /// The export file content (pretty-printed JSON).
  Future<String> exportJson({required String appVersion, DateTime? now}) async {
    final values = <String, String>{};
    for (final key in allowedKeys) {
      final raw = await _read(key);
      if (raw == null || raw.isEmpty) continue;
      values[key] = _configKeys.contains(key) ? _stripSecrets(raw) : raw;
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'formatVersion': formatVersion,
      'appVersion': appVersion,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'note': 'Ohne Passwörter und Zugangsdaten – diese nach dem Import neu eingeben.',
      'values': values,
    });
  }

  /// Writes the settings from [raw] (an export file). Unknown keys are
  /// ignored; backups and holiday plans are merged by id.
  Future<SettingsImportResult> importJson(String raw) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const SettingsFormatException('Die Datei ist kein gültiges JSON.');
    }
    if (decoded is! Map || decoded['format'] != format) {
      throw const SettingsFormatException('Das ist keine Heizungstrainer-Einstellungsdatei.');
    }
    final version = decoded['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw const SettingsFormatException(
          'Die Datei stammt aus einer neueren App-Version. Bitte zuerst die App aktualisieren.');
    }
    final values = decoded['values'];
    if (values is! Map) {
      throw const SettingsFormatException('Die Datei enthält keine Einstellungen.');
    }

    final allowed = allowedKeys.toSet();
    final imported = <String>[];
    final ignored = <String>[];
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String || !allowed.contains(key)) {
        ignored.add('$key');
        continue;
      }
      try {
        final String toWrite;
        if (_listKeys.contains(key)) {
          toWrite = _mergeById(await _read(key), value);
        } else if (_configKeys.contains(key)) {
          toWrite = _keepSecrets(await _read(key), value);
        } else {
          toWrite = value;
        }
        await _write(key, toWrite);
        imported.add(key);
      } on FormatException {
        ignored.add(key);
      } on TypeError {
        ignored.add(key);
      }
    }
    return SettingsImportResult(imported: imported, ignored: ignored);
  }

  static String _stripSecrets(String rawConfig) {
    final map = jsonDecode(rawConfig);
    if (map is! Map<String, dynamic>) return rawConfig;
    for (final k in map.keys.toList()) {
      if (_secretField.hasMatch(k) && map[k] is String) map[k] = '';
    }
    return jsonEncode(map);
  }

  /// Imported config, with secret fields taken from the existing config.
  static String _keepSecrets(String? existingRaw, String importedRaw) {
    final imported = jsonDecode(importedRaw) as Map<String, dynamic>;
    final existing = existingRaw == null ? null : jsonDecode(existingRaw);
    for (final k in imported.keys.toList()) {
      if (!_secretField.hasMatch(k)) continue;
      final old = existing is Map ? existing[k] : null;
      imported[k] = old is String ? old : '';
    }
    return jsonEncode(imported);
  }

  /// Union of both lists by `id`; on the same id the imported entry wins.
  static String _mergeById(String? existingRaw, String importedRaw) {
    final imported = (jsonDecode(importedRaw) as List).cast<Map<String, dynamic>>();
    final existing = existingRaw == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(existingRaw) as List).cast<Map<String, dynamic>>();
    final importedIds = imported.map((e) => e['id']).toSet();
    return jsonEncode([
      ...existing.where((e) => !importedIds.contains(e['id'])),
      ...imported,
    ]);
  }
}
