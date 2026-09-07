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

  /// Retrieves all user-created backups from storage, sorted newest first.
  Future<List<ConfigurationBackup>> getBackups() async {
    final inMem = _inMemory;
    if (inMem != null) {
      final raw = inMem[_storageKey];
      if (raw == null || raw.isEmpty) return [];
      final list = ConfigurationBackup.decodeList(raw);
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    }

    try {
      final raw = await _storage!
          .read(key: _storageKey)
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
      if (raw == null || raw.isEmpty) {
        return [];
      }
      final list = ConfigurationBackup.decodeList(raw);
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Saves a new backup to storage.
  Future<void> saveBackup(ConfigurationBackup backup) async {
    final existing = await getBackups();
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
    final existing = await getBackups();
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
