import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/models/telemetry_sample.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('DatabaseService Tests', () {
    late DatabaseService dbService;

    setUp(() async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService(preOpenedDb: db);
    });

    tearDown(() async {
      await dbService.close();
    });

    test('inserts and queries telemetry samples within time range', () async {
      final t0 = DateTime(2026, 9, 7, 10, 0);
      final t1 = DateTime(2026, 9, 7, 11, 0);
      final t2 = DateTime(2026, 9, 7, 12, 0);

      await dbService.insertTelemetry(TelemetrySample(
        timestamp: t0,
        outdoorTemp: 14.5,
        flowTemp: 45.0,
        returnTemp: 35.0,
        hotWaterTemp: 52.0,
        heatingCurveShift: 0.0,
        roomTarget: 20.0,
      ));

      await dbService.insertTelemetry(TelemetrySample(
        timestamp: t1,
        outdoorTemp: 12.0,
        flowTemp: 48.0,
        returnTemp: 37.0,
        hotWaterTemp: 51.5,
        heatingCurveShift: -1.0,
        roomTarget: 20.0,
      ));

      await dbService.insertTelemetry(TelemetrySample(
        timestamp: t2,
        outdoorTemp: 9.0,
        flowTemp: 52.0,
        returnTemp: 40.0,
        hotWaterTemp: 50.0,
        heatingCurveShift: -1.0,
        roomTarget: 20.0,
      ));

      final all = await dbService.getTelemetryHistory(
        from: t0,
        to: t2,
      );

      expect(all.length, 3);
      expect(all[0].flowTemp, 45.0);
      expect(all[0].spread, 10.0); // 45.0 - 35.0
      expect(all[1].flowTemp, 48.0);
      expect(all[1].heatingCurveShift, -1.0);
      expect(all[2].flowTemp, 52.0);

      // Range query excluding t0 and t2
      final middle = await dbService.getTelemetryHistory(
        from: DateTime(2026, 9, 7, 10, 30),
        to: DateTime(2026, 9, 7, 11, 30),
      );
      expect(middle.length, 1);
      expect(middle.first.outdoorTemp, 12.0);
    });

    test('prunes old telemetry samples based on retention window', () async {
      final oldTime = DateTime.now().subtract(const Duration(days: 100));
      final recentTime = DateTime.now().subtract(const Duration(days: 10));

      await dbService.insertTelemetry(TelemetrySample(
        timestamp: oldTime,
        outdoorTemp: 5.0,
        flowTemp: 55.0,
      ));
      await dbService.insertTelemetry(TelemetrySample(
        timestamp: recentTime,
        outdoorTemp: 15.0,
        flowTemp: 40.0,
      ));

      final deleted = await dbService.pruneOldTelemetry(
        retainDuration: const Duration(days: 90),
      );
      expect(deleted, 1);

      final remaining = await dbService.getTelemetryHistory(
        from: DateTime.now().subtract(const Duration(days: 365)),
        to: DateTime.now(),
      );
      expect(remaining.length, 1);
      expect(remaining.first.flowTemp, 40.0);
    });

    test('caches and restores controller readings for instant offline launch',
        () async {
      final now = DateTime(2026, 9, 7, 20, 15);
      final readings = {
        ECLRegisters.outdoorTemp.id: ECLReading(
          parameter: ECLRegisters.outdoorTemp,
          rawValue: 1250, // 12.50 °C
          timestamp: now,
        ),
        ECLRegisters.flowTemp.id: ECLReading(
          parameter: ECLRegisters.flowTemp,
          rawValue: 4800, // 48.00 °C
          timestamp: now,
        ),
        ECLRegisters.heatingCurveShift.id: ECLReading(
          parameter: ECLRegisters.heatingCurveShift,
          rawValue: -2,
          timestamp: now,
        ),
      };

      await dbService.cacheControllerReadings(readings);

      final cached = await dbService.getCachedControllerReadings();
      expect(cached.length, 3);
      expect(
        cached[ECLRegisters.outdoorTemp.id]?.displayValue,
        closeTo(12.5, 0.01),
      );
      expect(
        cached[ECLRegisters.flowTemp.id]?.displayValue,
        closeTo(48.0, 0.01),
      );
      expect(
        cached[ECLRegisters.heatingCurveShift.id]?.displayValue,
        -2.0,
      );
    });

    test('caches and restores Brunata billing and chart metrics', () async {
      final demo = BrunataMeterData.demo();
      await dbService.cacheBrunataData(demo);

      final cached = await dbService.getCachedBrunataData();
      expect(cached, isNotNull);
      expect(cached!.consumedKwh, demo.consumedKwh);
      expect(cached.currentBillingPeriodCost, demo.currentBillingPeriodCost);
      expect(cached.charts.length, demo.charts.length);
      expect(cached.hasDetail, isTrue);
    });
  });

  group('ECLProvider SQLite Integration', () {
    test('initializes with cached data from SQLite in 0ms', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final dbService = DatabaseService(preOpenedDb: db);

      // Pre-seed cache in SQLite
      final now = DateTime(2026, 9, 7, 20, 30);
      await dbService.cacheControllerReadings({
        ECLRegisters.flowTemp.id: ECLReading(
          parameter: ECLRegisters.flowTemp,
          rawValue: 5120, // 51.20 °C
          timestamp: now,
        ),
      });
      await dbService.cacheBrunataData(BrunataMeterData.demo());

      // Create provider with database
      final provider = ECLProvider(
        databaseService: dbService,
        autoLoadDatabase: true,
      );

      // Wait a tick for async cache load
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.hasCachedReadings, isTrue);
      expect(
        provider.getReading(ECLRegisters.flowTemp)?.displayValue,
        closeTo(51.2, 0.01),
      );
      expect(provider.brunataData, isNotNull);

      // Offline mode toggling
      expect(provider.isOfflineMode, isFalse);
      provider.openOfflineMode();
      expect(provider.isOfflineMode, isTrue);
      provider.exitOfflineMode();
      expect(provider.isOfflineMode, isFalse);

      provider.dispose();
      await dbService.close();
    });
  });
}
