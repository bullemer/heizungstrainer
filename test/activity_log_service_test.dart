import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/database_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  group('ActivityLogEntry Model Tests', () {
    test('serializes toMap and deserializes fromMap with JSON details', () {
      final entry = ActivityLogEntry.create(
        level: ActivityLogLevel.warning,
        category: ActivityLogCategory.controllerRead,
        controllerId: 'danfoss_ecl_310',
        action: 'SENSOR_FAULT_DETECTED',
        message: 'Sensorfehler 19200 an S3 (Rücklauf) erkannt.',
        details: {'parameterId': 'return_temp', 'rawValue': 19200},
        errorCode: 'SENSOR_FAULT_19200',
      );

      final map = entry.toMap();
      expect(map['level'], 'warning');
      expect(map['category'], 'controllerRead');
      expect(map['controller_id'], 'danfoss_ecl_310');
      expect(map['action'], 'SENSOR_FAULT_DETECTED');
      expect(map['error_code'], 'SENSOR_FAULT_19200');
      expect(map['user_acknowledged'], 0);

      final restored = ActivityLogEntry.fromMap({
        ...map,
        'id': 42,
      });

      expect(restored.id, 42);
      expect(restored.level, ActivityLogLevel.warning);
      expect(restored.category, ActivityLogCategory.controllerRead);
      expect(restored.controllerId, 'danfoss_ecl_310');
      expect(restored.errorCode, 'SENSOR_FAULT_19200');
      expect(restored.details?['rawValue'], 19200);
      expect(restored.userAcknowledged, isFalse);
    });

    test('anonymizes sensitive credentials in toJson for backoffice transmission', () {
      final entry = ActivityLogEntry.create(
        level: ActivityLogLevel.error,
        category: ActivityLogCategory.billing,
        action: 'PORTAL_AUTH_ERROR',
        message: 'Fehler bei der Anmeldung im Portal',
        details: {
          'username': 'user123',
          'password': 'SuperSecretPassword!',
          'token': 'Bearer secret-jwt-token',
          'errorCode': 401,
        },
        errorCode: 'AUTH_FAILED',
      );

      final json = entry.toJson(anonymize: true);
      final details = json['details'] as Map<String, dynamic>;

      expect(details['username'], 'user123');
      expect(details.containsKey('password'), isFalse);
      expect(details.containsKey('token'), isFalse);
      expect(json['errorCode'], 'AUTH_FAILED');
    });
  });

  group('ActivityLogService SQLite & Workflow Tests', () {
    late DatabaseService dbService;
    late ActivityLogService logService;

    setUp(() async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService(preOpenedDb: db);
      logService = ActivityLogService(
        databaseService: dbService,
        enablePersistence: true,
        enableRemoteDispatch: false,
      );
      await logService.init();
    });

    tearDown(() async {
      await dbService.close();
    });

    test('logs reads, writes, connections, and security gates', () async {
      // 1. Controller Read
      await logService.logRead(
        controllerId: 'danfoss_ecl_310',
        action: 'READ_TELEMETRY',
        message: 'Messwertabruf erfolgreich',
        details: {'flow': 45.2, 'return': 36.1},
      );

      // 2. Controller Write
      await logService.logWrite(
        controllerId: 'danfoss_ecl_310',
        action: 'WRITE_PARAMETER',
        message: 'Heizkurve angepasst',
        details: {'shift': 2.0},
        success: true,
      );

      // 3. Security Gate
      await logService.logSecurityGate(
        controllerId: 'danfoss_ecl_310',
        message: 'Schreibwert über Maximum verriegelt',
        details: {'target': 95.0, 'max': 80.0},
        errorCode: 'WRITE_OUT_OF_BOUNDS',
      );

      // 4. Connection
      await logService.logConnection(
        controllerId: 'danfoss_ecl_310',
        action: 'CONNECTED',
        message: 'Verbunden mit 192.168.1.50',
      );

      expect(logService.recentEntries.length, 4);

      // Check stats from DB
      final stats = await dbService.getActivityLogStats();
      expect(stats['total'], 4);
      expect(stats['writes'], 1);
      expect(stats['reads'], 1);
      expect(stats['warnings'], 1); // security gate is warning
    });

    test('generates diagnostic report with user acknowledgment workflow', () async {
      // Log an error
      await logService.logError(
        action: 'MODBUS_TIMEOUT',
        message: 'Timeout beim Lesen von Register 10200',
        controllerId: 'danfoss_ecl_310',
        category: ActivityLogCategory.controllerRead,
        errorCode: 'MODBUS_TIMEOUT',
      );

      final report = logService.generateDiagnosticReport(
        currentControllerId: 'danfoss_ecl_310',
        currentBillingId: 'brunata_hamburg',
        userNote: 'Regler verliert nach 2 Stunden Verbindung',
      );

      expect(report['app']['name'], 'Heizungstrainer');
      expect(report['systemContext']['controllerId'], 'danfoss_ecl_310');
      expect(report['userConsent']['userAcknowledged'], isTrue);
      expect(report['userConsent']['userNote'], 'Regler verliert nach 2 Stunden Verbindung');
      expect((report['criticalErrors'] as List).isNotEmpty, isTrue);

      // Verify sending without acknowledgment throws ArgumentError
      expect(
        () => logService.sendDiagnosticReport(
          diagnosticPayload: report,
          userHasAcknowledged: false,
        ),
        throwsArgumentError,
      );

      // Send with user acknowledgment
      final success = await logService.sendDiagnosticReport(
        diagnosticPayload: report,
        userHasAcknowledged: true,
      );
      expect(success, isTrue);

      // Verify marked as acknowledged
      expect(logService.recentEntries.any((e) => e.userAcknowledged), isTrue);
    });

    test('clearLogs purges memory and database', () async {
      await logService.logRead(
        controllerId: 'test',
        action: 'POLL',
        message: 'Test Poll',
      );
      expect(logService.recentEntries.length, 1);

      await logService.clearLogs();
      expect(logService.recentEntries.isEmpty, isTrue);

      final stats = await dbService.getActivityLogStats();
      expect(stats['total'], 0);
    });
  });
}
