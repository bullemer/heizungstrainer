import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/models/telemetry_sample.dart';

/// Local SQLite database service providing persistent time-series buffering,
/// offline state caching, and Brunata billing synchronization.
class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService();

  final DatabaseFactory? _factory;
  final String? _customPath;
  Database? _db;
  bool _tablesCreated = false;

  DatabaseService({
    DatabaseFactory? databaseFactory,
    String? customPath,
    Database? preOpenedDb,
  })  : _factory = databaseFactory,
        _customPath = customPath,
        _db = preOpenedDb;

  /// Visible for testing to reset the singleton.
  static void resetInstance([DatabaseService? newInstance]) {
    _instance = newInstance;
  }

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      if (!_tablesCreated) {
        await _createTables(_db!);
        _tablesCreated = true;
      }
      return _db!;
    }
    _db = await _initDatabase();
    if (!_tablesCreated) {
      await _createTables(_db!);
      _tablesCreated = true;
    }
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final factory = _getDatabaseFactory();

    final String dbPath;
    if (_customPath != null) {
      dbPath = _customPath;
    } else {
      final databasesPath = await factory.getDatabasesPath();
      dbPath = p.join(databasesPath, 'heizungstrainer.db');
    }

    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onOpen: (db) async {
          await _createTables(db);
        },
      ),
    );
    await _createTables(db);
    return db;
  }

  DatabaseFactory _getDatabaseFactory() {
    if (_factory != null) return _factory;

    // Use FFI for Desktop and test platforms
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  Future<void> _createTables(Database db) async {
    // 1. Time-series historical telemetry
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sensor_telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        outdoor_temp REAL,
        flow_temp REAL,
        return_temp REAL,
        hot_water_temp REAL,
        heating_curve_shift REAL,
        room_target REAL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_telemetry_timestamp 
      ON sensor_telemetry (timestamp);
    ''');

    // 2. Controller snapshot cache for instant 0ms offline launch
    await db.execute('''
      CREATE TABLE IF NOT EXISTS controller_cache (
        parameter_id TEXT PRIMARY KEY,
        raw_value INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // 3. Brunata billing & community metrics cache
    await db.execute('''
      CREATE TABLE IF NOT EXISTS brunata_cache (
        key TEXT PRIMARY KEY,
        json_data TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // 4. In-app activity and error diagnostic logs
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        level TEXT NOT NULL,
        category TEXT NOT NULL,
        controller_id TEXT,
        action TEXT NOT NULL,
        message TEXT NOT NULL,
        details TEXT,
        error_code TEXT,
        user_acknowledged INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_timestamp 
      ON activity_logs (timestamp);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_level 
      ON activity_logs (level);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_category 
      ON activity_logs (category);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_error_code 
      ON activity_logs (error_code);
    ''');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Telemetry Time-Series
  // ──────────────────────────────────────────────────────────────────────────

  /// Inserts a new telemetry sample into the database.
  Future<int> insertTelemetry(TelemetrySample sample) async {
    final db = await database;
    return await db.insert('sensor_telemetry', sample.toMap());
  }

  /// Retrieves telemetry records within a time range, ordered by timestamp ascending.
  Future<List<TelemetrySample>> getTelemetryHistory({
    required DateTime from,
    required DateTime to,
    int? limit,
  }) async {
    final db = await database;
    final rows = await db.query(
      'sensor_telemetry',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [
        from.millisecondsSinceEpoch,
        to.millisecondsSinceEpoch,
      ],
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    return rows.map((r) => TelemetrySample.fromMap(r)).toList();
  }

  /// Deletes telemetry samples older than the given [retainDuration].
  Future<int> pruneOldTelemetry({
    Duration retainDuration = const Duration(days: 90),
  }) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(retainDuration).millisecondsSinceEpoch;
    return await db.delete(
      'sensor_telemetry',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Controller State Cache
  // ──────────────────────────────────────────────────────────────────────────

  /// Persists the latest controller readings to provide instant offline display.
  Future<void> cacheControllerReadings(Map<String, ECLReading> readings) async {
    if (readings.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final entry in readings.entries) {
      batch.insert(
        'controller_cache',
        {
          'parameter_id': entry.key,
          'raw_value': entry.value.rawValue,
          'updated_at': entry.value.timestamp.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Loads cached controller readings from the database.
  Future<Map<String, ECLReading>> getCachedControllerReadings() async {
    final db = await database;
    final rows = await db.query('controller_cache');
    final result = <String, ECLReading>{};

    final paramMap = {for (final p in ECLRegisters.all) p.id: p};

    for (final row in rows) {
      final paramId = row['parameter_id'] as String;
      final param = paramMap[paramId];
      if (param != null) {
        final rawValue = row['raw_value'] as int;
        final updatedAt = row['updated_at'] as int;
        result[paramId] = ECLReading(
          parameter: param,
          rawValue: rawValue,
          timestamp: DateTime.fromMillisecondsSinceEpoch(updatedAt),
        );
      }
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Brunata Data Cache
  // ──────────────────────────────────────────────────────────────────────────

  /// Persists scraped Brunata data for offline and instant display.
  Future<void> cacheBrunataData(BrunataMeterData data) async {
    final db = await database;
    await db.insert(
      'brunata_cache',
      {
        'key': 'latest',
        'json_data': jsonEncode(data.toJson()),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Loads cached Brunata data if available.
  Future<BrunataMeterData?> getCachedBrunataData() async {
    final db = await database;
    final rows = await db.query(
      'brunata_cache',
      where: 'key = ?',
      whereArgs: ['latest'],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final rawJson = rows.first['json_data'] as String;
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      return BrunataMeterData.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Returns the timestamp of the last successful billing data sync, or null if never synced.
  Future<DateTime?> getLastBillingSyncTime() async {
    final db = await database;
    final rows = await db.query(
      'brunata_cache',
      columns: ['updated_at'],
      where: 'key = ?',
      whereArgs: ['latest'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final updatedAt = rows.first['updated_at'] as int;
    return DateTime.fromMillisecondsSinceEpoch(updatedAt);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Activity and Diagnostic Logging
  // ──────────────────────────────────────────────────────────────────────────

  /// Inserts a new activity log record into SQLite.
  Future<int> insertActivityLog(ActivityLogEntry entry) async {
    final db = await database;
    return await db.insert('activity_logs', entry.toMap());
  }

  /// Retrieves activity logs with optional category, level, error code, or query filtering.
  Future<List<ActivityLogEntry>> getActivityLogs({
    ActivityLogCategory? category,
    ActivityLogLevel? level,
    String? errorCode,
    bool? errorsOnly,
    String? searchQuery,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (category != null) {
      whereClauses.add('category = ?');
      whereArgs.add(category.toDbString());
    }

    if (level != null) {
      whereClauses.add('level = ?');
      whereArgs.add(level.toDbString());
    } else if (errorsOnly == true) {
      whereClauses.add("(level = 'error' OR level = 'warning')");
    }

    if (errorCode != null && errorCode.isNotEmpty) {
      whereClauses.add('error_code = ?');
      whereArgs.add(errorCode);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      whereClauses.add(
        '(message LIKE ? OR action LIKE ? OR error_code LIKE ? OR controller_id LIKE ?)',
      );
      whereArgs.addAll([term, term, term, term]);
    }

    final whereString =
        whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final rows = await db.query(
      'activity_logs',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map((r) => ActivityLogEntry.fromMap(r)).toList();
  }

  /// Helper to extract first integer value from count queries.
  int _firstIntValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.values.isEmpty) return 0;
    final val = rows.first.values.first;
    return val is int ? val : 0;
  }

  /// Calculates quick stats for the log overview banner.
  Future<Map<String, int>> getActivityLogStats() async {
    final db = await database;

    final totalResult = _firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM activity_logs'),
    );

    final errorResult = _firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM activity_logs WHERE level = 'error'",
      ),
    );

    final warningResult = _firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM activity_logs WHERE level = 'warning'",
      ),
    );

    final writesResult = _firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM activity_logs WHERE category = 'controllerWrite'",
      ),
    );

    final readsResult = _firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM activity_logs WHERE category = 'controllerRead'",
      ),
    );

    return {
      'total': totalResult,
      'errors': errorResult,
      'warnings': warningResult,
      'writes': writesResult,
      'reads': readsResult,
    };
  }

  /// Marks specified log entries (or all unacknowledged) as acknowledged by the user.
  Future<int> markLogsAcknowledged({List<int>? ids}) async {
    final db = await database;
    if (ids != null && ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      return await db.rawUpdate(
        'UPDATE activity_logs SET user_acknowledged = 1 WHERE id IN ($placeholders)',
        ids,
      );
    }
    return await db.update(
      'activity_logs',
      {'user_acknowledged': 1},
      where: 'user_acknowledged = 0',
    );
  }

  /// Deletes all activity logs.
  Future<int> clearActivityLogs() async {
    final db = await database;
    return await db.delete('activity_logs');
  }

  /// Deletes logs older than [retainDuration] to keep disk usage light.
  Future<int> pruneOldActivityLogs({
    Duration retainDuration = const Duration(days: 30),
  }) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(retainDuration).millisecondsSinceEpoch;
    return await db.delete(
      'activity_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  /// Clears all tables in the database.
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('sensor_telemetry');
    await db.delete('controller_cache');
    await db.delete('brunata_cache');
    await db.delete('activity_logs');
  }

  /// Closes the database connection.
  Future<void> close() async {
    _tablesCreated = false;
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
