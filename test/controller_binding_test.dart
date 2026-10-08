import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/controller_binding.dart';
import 'package:heizungstrainer/services/license_key.dart';
import 'package:heizungstrainer/services/license_service.dart';

import 'license_service_test.dart' as lt;

class _Driver implements HeatingController {
  double room = 21;
  final writes = <double>[];
  @override
  String get id => 'nibe_modbus';
  @override
  String get brandName => 'NIBE';
  @override
  String get modelName => 'Test';
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
  Future<void> setHeatingCurveShift(double shift) async {}
  @override
  Future<void> setRoomTarget(double t) async {
    writes.add(t);
    room = t;
  }
}

Future<ECLProvider> _provider(LicenseService license, ActivityLogService log, Map<String, String> bindingMemory) async {
  final p = ECLProvider(
    logService: log,
    licenseService: license,
    bindingStore: ControllerBindingStore(inMemoryStorage: bindingMemory),
    autoLoadDatabase: false,
  );
  await p.setSelectedController('nibe_modbus');
  await p.setBetaWritesEnabled(true);
  return p;
}

Future<_Driver> _connectTo(ECLProvider p, String ip) async {
  if (p.isConnected) p.disconnect();
  final d = _Driver();
  p.useControllerForTesting(d);
  p.setConnectedForTesting(ip: ip);
  await p.refreshReadings();
  return d;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('Master edition (2) is accepted and marks the licence as Master; unknown editions are not', () async {
    final issuer = await lt.TestIssuer.create();
    final s = LicenseService(inMemoryStorage: {}, publicKey: issuer.publicKey);
    expect(await s.activateOfflineKey(await issuer.issue(edition: LicenseKeyCodec.editionMaster)), isTrue);
    expect(s.isMaster, isTrue);
    expect(s.isPro, isTrue);
    final pro = LicenseService(inMemoryStorage: {}, publicKey: issuer.publicKey);
    expect(await pro.activateOfflineKey(await issuer.issue()), isTrue);
    expect(pro.isMaster, isFalse);
    expect(await LicenseService(inMemoryStorage: {}, publicKey: issuer.publicKey).activateOfflineKey(await issuer.issue(edition: 3)),
        isFalse);
  });

  test('first controller becomes "own"; another one is read-only; switch once per 12 months', () async {
    final log = ActivityLogService(enablePersistence: false, enableRemoteDispatch: false);
    final memory = <String, String>{};
    final p = await _provider(LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro), log, memory);

    final own = await _connectTo(p, '192.168.1.10');
    expect(p.controllerAccess, ControllerAccess.own);
    expect(p.controllerBinding!.identity, 'nibe_modbus@192.168.1.10');
    await p.writeParameter(ECLRegisters.roomTargetTemp, 20);
    expect(own.writes, [20]);

    final other = await _connectTo(p, '192.168.1.99');
    expect(p.controllerAccess, ControllerAccess.foreign);
    expect(p.getReading(ECLRegisters.roomTargetTemp), isNotNull); // reading works
    await expectLater(p.writeParameter(ECLRegisters.roomTargetTemp, 19),
        throwsA(isA<ModbusCommunicationException>().having((e) => e.message, 'm', contains('Master-Lizenz'))));
    expect(other.writes, isEmpty);
    expect(log.recentEntries.any((e) => e.errorCode == 'CONTROLLER_NOT_BOUND'), isTrue);

    // switch to the other controller (allowed once)
    await p.rebindToConnectedController();
    expect(p.controllerAccess, ControllerAccess.own);
    await p.writeParameter(ECLRegisters.roomTargetTemp, 19);
    expect(other.writes, [19]);
    expect(p.nextBindingChange, isNotNull);

    // back at the first one: read-only, and no second switch within 12 months
    await _connectTo(p, '192.168.1.10');
    expect(p.controllerAccess, ControllerAccess.foreign);
    await expectLater(p.rebindToConnectedController(), throwsA(isA<ModbusCommunicationException>()));

    // binding survives an app restart (same storage)
    final restarted = await _provider(LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro), log, memory);
    await _connectTo(restarted, '192.168.1.99');
    expect(restarted.controllerAccess, ControllerAccess.own);
  });

  test('Master licence: any controller can be changed', () async {
    final issuer = await lt.TestIssuer.create();
    final license = LicenseService(inMemoryStorage: {}, publicKey: issuer.publicKey);
    await license.activateOfflineKey(await issuer.issue(edition: LicenseKeyCodec.editionMaster));
    final p = await _provider(license, ActivityLogService(enablePersistence: false, enableRemoteDispatch: false), {
      ControllerBindingStore.storageKey: '{"id":"danfoss:087H3040:1-1","label":"Alt","boundAt":"2026-01-01T00:00:00.000"}',
    });
    final d = await _connectTo(p, '10.0.0.5');
    expect(p.controllerAccess, ControllerAccess.unrestricted);
    await p.writeParameter(ECLRegisters.roomTargetTemp, 22);
    expect(d.writes, [22]);
  });

  test('demo mode is never restricted', () async {
    final p = ECLProvider(
      logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
      bindingStore: ControllerBindingStore(inMemoryStorage: {
        ControllerBindingStore.storageKey: '{"id":"x","label":"Alt","boundAt":"2026-01-01T00:00:00.000"}',
      }),
      autoLoadDatabase: false,
    );
    await p.startSimulation();
    expect(p.controllerAccess, ControllerAccess.unrestricted);
    await p.writeParameter(ECLRegisters.roomTargetTemp, 22.5);
    p.dispose();
  });
}
