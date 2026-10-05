import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/configuration_backup.dart';

/// Manages persistent storage and retrieval of heating controller backups.
class BackupService {
  static const String _storageKey = 'ecl_controller_backups';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _inMemory;

  BackupService({
    FlutterSecureStorage? storage,
    Map<String, String>? inMemoryStorage,
  })  : _storage = inMemoryStorage != null
            ? null
            : (storage ?? const FlutterSecureStorage()),
        _inMemory = inMemoryStorage;

  /// Reads all backups. Throws if storage can't be read or decoded, so a
  /// slow keystore or one bad entry never looks like "no backups" to
  /// [saveBackup]/[deleteBackup], which would then overwrite all of them.
  Future<List<ConfigurationBackup>> _readBackups() async {
    final String? raw;
    final inMem = _inMemory;
    if (inMem != null) {
      raw = inMem[_storageKey];
    } else {
      raw = await _storage!
          .read(key: _storageKey)
          .timeout(const Duration(seconds: 5));
    }
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((item) => ConfigurationBackup.fromJson(item as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  /// Retrieves all user-created backups from storage, sorted newest first.
  /// For display only: returns an empty list if storage can't be read.
  Future<List<ConfigurationBackup>> getBackups() async {
    try {
      return await _readBackups();
    } catch (e) {
      debugPrint('[BackupService] Could not read backups: $e');
      return [];
    }
  }

  /// Saves a new backup to storage.
  Future<void> saveBackup(ConfigurationBackup backup) async {
    final existing = await _readBackups();
    final updated = [backup, ...existing.where((b) => b.id != backup.id)];
    final encoded = ConfigurationBackup.encodeList(updated);

    final inMem = _inMemory;
    if (inMem != null) {
      inMem[_storageKey] = encoded;
      return;
    }
    await _storage!.write(key: _storageKey, value: encoded);
  }

  /// Deletes a backup by its ID.
  Future<void> deleteBackup(String id) async {
    final existing = await _readBackups();
    final updated = existing.where((b) => b.id != id).toList();
    final encoded = ConfigurationBackup.encodeList(updated);

    final inMem = _inMemory;
    if (inMem != null) {
      inMem[_storageKey] = encoded;
      return;
    }
    await _storage!.write(key: _storageKey, value: encoded);
  }

  /// Clears all backups from storage.
  Future<void> clearBackups() async {
    final inMem = _inMemory;
    if (inMem != null) {
      inMem.remove(_storageKey);
      return;
    }
    await _storage!.delete(key: _storageKey);
  }
}
