import 'dart:async';
import 'package:heizungstrainer/services/modbus_service.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/controllers/mock_heating_controller.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/database_service.dart';

class _DelayedController extends MockHeatingController {
  final started = Completer<void>();
  final response = Completer<ControllerTelemetry>();
  int reads = 0;
  @override
  Future<ControllerTelemetry> readTelemetry() {
    reads++;
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}

class _PendingConnect extends ModbusService {
  final started = Completer<void>();
  final done = Completer<void>();
  @override
  Future<void> connect(String ip, {int port = 502}) {
    started.complete();
    return done.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('cancelled Modbus connect cannot reopen the service', () async {
    final modbus = ModbusService();
    final pending = modbus.connect('127.0.0.1', port: 1);
    await modbus.disconnect();
    await pending;
    expect(modbus.isConnected, isFalse);
    expect(modbus.currentIp, isNull);
  });

  test('cancelled connection cannot put the provider back online', () async {
    final modbus = _PendingConnect();
    final p = ECLProvider(modbusService: modbus, autoLoadDatabase: false);
    await p.reloadSettings();
    final pending = p.connectToIp('127.0.0.1');
    await modbus.started.future;
    p.disconnect();
    modbus.done.complete();
    await pending;
    expect(p.connectionState, ECLConnectionState.disconnected);
    expect(p.readings, isEmpty);
    p.dispose();
  });

  test('Danfoss demo exposes its curve without persisting fake hardware history', () async {
    sqfliteFfiInit();
    final db = DatabaseService(preOpenedDb: await databaseFactoryFfi.openDatabase(inMemoryDatabasePath));
    addTearDown(db.close);
    final p = ECLProvider(autoLoadDatabase: false, databaseService: db);
    await p.reloadSettings();
    await p.startSimulation();
    expect(ControllerHeatingCurve.fromReadings(p.getReading), isNotNull);
    expect(await db.getCachedControllerReadings(), isEmpty);
    expect(await db.getTelemetryHistory(from: DateTime(2000), to: DateTime(2100)), isEmpty);
    p.disconnect();
    expect(ControllerHeatingCurve.fromReadings(p.getReading), isNull);
    p.dispose();
  });

  test('switching from demo billing to Brunata clears demo consumption', () async {
    final p = ECLProvider(autoLoadDatabase: false);
    await p.reloadSettings();
    await p.setSelectedBillingProvider('techem');
    p.setBrunataDataForTesting(BrunataMeterData.demo());
    await p.setSelectedBillingProvider('brunata_hamburg');
    expect(p.brunataData, isNull);
    expect(p.hasRealBillingData, isFalse);
    expect(p.annualHeatingKwh, isNull);
    p.dispose();
  });

  test('billing caches and sync timestamps are isolated by source', () async {
    sqfliteFfiInit();
    final db = DatabaseService(preOpenedDb: await databaseFactoryFfi.openDatabase(inMemoryDatabasePath));
    addTearDown(db.close);
    await db.cacheBrunataData(BrunataMeterData.demo(), providerId: 'techem');
    expect(await db.getCachedBrunataData(), isNull);
    expect(await db.getLastBillingSyncTime(), isNull);
    expect(await db.getCachedBrunataData(providerId: 'techem'), isNotNull);
    expect(await db.getLastBillingSyncTime(providerId: 'techem'), isNotNull);
    // The old unlabelled cache can contain demo values: do not migrate it as real.
    await (await db.database).rawUpdate("UPDATE brunata_cache SET key = 'latest'");
    expect(await db.getCachedBrunataData(), isNull);
  });

  for (final fail in [false, true]) {
    test('late ${fail ? 'error' : 'read'} after disconnect does not restore state', () async {
      final p = ECLProvider(autoLoadDatabase: false);
      await p.reloadSettings();
      final driver = _DelayedController();
      p.useControllerForTesting(driver);
      p.setConnectedForTesting(ip: 'Simulation');
      final pending = p.refreshReadings();
      await driver.started.future;
      await p.refreshReadings();
      expect(driver.reads, 1, reason: 'manual refresh must not overlap polling');
      p.disconnect();
      if (fail) {
        driver.response.completeError(StateError('old connection lost'));
      } else {
        driver.response.complete(ControllerTelemetry(timestamp: DateTime.now(), flowTemp: 70));
      }
      await pending;
      expect(p.readings, isEmpty);
      expect(p.lastSuccessfulPoll, isNull);
      expect(p.connectionState, ECLConnectionState.disconnected);
      expect(p.errorMessage, isNull);
      p.dispose();
    });
  }
}
