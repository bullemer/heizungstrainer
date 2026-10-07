import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/controller_settings_watch.dart';
import 'package:heizungstrainer/services/license_service.dart';

void main() {
  group('ControllerSettingsWatch', () {
    const id = 'danfoss_ecl_310';
    final room = ECLRegisters.roomTargetTemp.id;
    final p15 = ECLRegisters.curvePoints[1].id;

    test('first look is a baseline, later changes are reported', () async {
      final store = <String, String>{};
      final watch = ControllerSettingsWatch(inMemoryStorage: store);
      expect(await watch.compare(id, {room: 21, p15: 36}), isEmpty);
      expect(await watch.compare(id, {room: 21, p15: 36}), isEmpty);

      final diffs = await watch.compare(id, {room: 21, p15: 38});
      expect(diffs, hasLength(1));
      expect(diffs.single.parameter.id, p15);
      expect(diffs.single.known.value, 36);
      expect(diffs.single.live, 38);
      expect(diffs.single.appChangeMissing, isFalse);

      // persisted: a new instance knows 38 already
      expect(await ControllerSettingsWatch(inMemoryStorage: store).compare(id, {p15: 38}), isEmpty);
    });

    test('an app write that the controller no longer shows is flagged', () async {
      final watch = ControllerSettingsWatch(inMemoryStorage: {});
      await watch.compare(id, {room: 22});
      await watch.recordAppWrite(id, ECLRegisters.roomTargetTemp, 21);
      expect(await watch.compare(id, {room: 21}), isEmpty);

      final diffs = await watch.compare(id, {room: 22});
      expect(diffs.single.appChangeMissing, isTrue);
      expect(diffs.single.known.value, 21);
      // after reporting, the controller value is the new baseline
      expect(await watch.compare(id, {room: 22}), isEmpty);
    });

    test('rounding noise below 0.05 is ignored', () async {
      final watch = ControllerSettingsWatch(inMemoryStorage: {});
      await watch.compare(id, {room: 21.0});
      expect(await watch.compare(id, {room: 21.04}), isEmpty);
    });
  });

  group('ECLProvider settings check', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    Future<(ECLProvider, _FakeController, ActivityLogService)> connected() async {
      final fake = _FakeController(room: 22);
      final log = ActivityLogService(enablePersistence: false, enableRemoteDispatch: false);
      final provider = ECLProvider(
        logService: log,
        licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
        autoLoadDatabase: false,
      );
      await provider.setSelectedController('nibe_modbus');
      provider.useControllerForTesting(fake);
      provider.setConnectedForTesting(ip: '192.168.178.60');
      await provider.setBetaWritesEnabled(true);
      await provider.refreshReadings();
      return (provider, fake, log);
    }

    List<ActivityLogEntry> byAction(ActivityLogService log, String action) =>
        log.recentEntries.where((e) => e.action == action).toList();

    test('first poll logs a settings check, writes log before → after', () async {
      final (provider, _, log) = await connected();
      expect(byAction(log, 'SETTINGS_CHECK'), hasLength(1));

      await provider.writeParameter(ECLRegisters.roomTargetTemp, 21);
      final write = byAction(log, 'WRITE_PARAMETER_VERIFIED').single;
      expect(write.message, contains('22 → 21 °C'));
      expect(write.details?['previousValue'], 22);
      expect(write.details?['controllerValue'], 21);
    });

    test('change outside the app → warning; lost app change → error', () async {
      final (provider, fake, log) = await connected();

      fake.room = 23; // someone changes it at the controller
      await provider.refreshReadings();
      final ext = byAction(log, 'SETTING_CHANGED_OUTSIDE_APP').single;
      expect(ext.level, ActivityLogLevel.warning);
      expect(ext.message, contains('22 → 23'));

      await provider.writeParameter(ECLRegisters.roomTargetTemp, 20);
      fake.room = 21; // app's value vanished from the controller
      await provider.refreshReadings();
      final err = byAction(log, 'APP_CHANGE_NOT_ON_DEVICE').single;
      expect(err.level, ActivityLogLevel.error);
      expect(err.errorCode, 'APP_CHANGE_NOT_ON_DEVICE');
      expect(err.message, contains('20 → 21'));
    });

    test('checkControllerSettings returns app vs controller rows', () async {
      final (provider, fake, _) = await connected();
      await provider.writeParameter(ECLRegisters.roomTargetTemp, 21);
      fake.room = 19;
      final rows = await provider.checkControllerSettings();
      final row = rows.singleWhere((r) => r.parameter.id == ECLRegisters.roomTargetTemp.id);
      expect(row.known?.value, 21);
      expect(row.known?.source, SettingSource.app);
      expect(row.live, 19);
      expect(row.differs, isTrue);
    });
  });
}

class _FakeController implements HeatingController {
  _FakeController({required this.room});
  double room;

  @override
  String get id => 'nibe_modbus';
  @override
  String get brandName => 'Test';
  @override
  String get modelName => 'Fake';
  @override
  ConnectionProtocol get protocol => ConnectionProtocol.modbusTcp;
  @override
  HeatingCapabilities get capabilities => const HeatingCapabilities(supportsHeatingCurveShift: false);
  @override
  bool get isConnected => true;
  @override
  Stream<ControllerTelemetry> get telemetryStream => const Stream.empty();
  @override
  Future<void> connect({required String host, int? port, Map<String, dynamic>? extraConfig}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<ControllerTelemetry> readTelemetry() async =>
      ControllerTelemetry(timestamp: DateTime.now(), flowTemp: 30, roomTarget: room);
  @override
  Future<void> setHeatingCurveShift(double shift) async => throw UnsupportedError('no shift');
  @override
  Future<void> setRoomTarget(double temperature) async => room = temperature;
}
