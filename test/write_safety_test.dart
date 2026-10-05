import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/license_service.dart';
import 'package:heizungstrainer/services/tls_policy.dart';

/// Driver double: reports only what it is given and can ignore writes, like a
/// controller that acknowledges a request but does not apply it.
class FakeController implements HeatingController {
  FakeController({
    this.caps = const HeatingCapabilities(minShift: -10, maxShift: 10),
    this.flowTemp,
    this.shift,
    this.ignoreWrites = false,
  });

  final HeatingCapabilities caps;
  double? flowTemp;
  double? shift;
  double? room;
  bool ignoreWrites;
  final writes = <double>[];

  @override
  String get id => 'nibe_modbus';
  @override
  String get brandName => 'NIBE';
  @override
  String get modelName => 'Fake';
  @override
  ConnectionProtocol get protocol => ConnectionProtocol.modbusTcp;
  @override
  HeatingCapabilities get capabilities => caps;
  @override
  bool get isConnected => true;
  @override
  Stream<ControllerTelemetry> get telemetryStream => const Stream.empty();
  @override
  Future<void> connect({required String host, int? port, Map<String, dynamic>? extraConfig}) async {}
  @override
  Future<void> disconnect() async {}

  @override
  Future<ControllerTelemetry> readTelemetry() async => ControllerTelemetry(
        timestamp: DateTime.now(),
        flowTemp: flowTemp,
        heatingCurveShift: shift,
        roomTarget: room,
      );

  @override
  Future<void> setHeatingCurveShift(double value) async {
    writes.add(value);
    if (!ignoreWrites) shift = value;
  }

  @override
  Future<void> setRoomTarget(double value) async {
    if (!ignoreWrites) room = value;
  }
}

Future<ECLProvider> providerWith(FakeController fake, {bool allowBetaWrites = true}) async {
  final provider = ECLProvider(
    logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
    licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
    autoLoadDatabase: false,
  );
  await provider.setSelectedController('nibe_modbus');
  provider.useControllerForTesting(fake);
  provider.setConnectedForTesting(ip: '192.168.178.60');
  if (allowBetaWrites) await provider.setBetaWritesEnabled(true);
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Beta write gate', () {
    test('unverified driver is read-only by default', () async {
      final fake = FakeController(shift: 0);
      final provider = await providerWith(fake, allowBetaWrites: false);

      expect(provider.isBetaController, isTrue);
      expect(provider.isBetaWriteBlocked, isTrue);
      await expectLater(
        provider.writeParameter(ECLRegisters.heatingCurveShift, 2),
        throwsA(isA<ModbusCommunicationException>().having(
            (e) => e.message, 'message', contains('Beta-Modus'))),
      );
      expect(fake.writes, isEmpty);
    });

    test('explicit opt-in allows writes, revoking blocks again', () async {
      final fake = FakeController(shift: 0);
      final provider = await providerWith(fake, allowBetaWrites: false);

      await provider.setBetaWritesEnabled(true);
      await provider.writeParameter(ECLRegisters.heatingCurveShift, 2);
      expect(fake.writes, [2]);

      await provider.setBetaWritesEnabled(false);
      await expectLater(
        provider.writeParameter(ECLRegisters.heatingCurveShift, 1),
        throwsA(isA<ModbusCommunicationException>()),
      );
      expect(fake.writes, [2]);
    });

    test('opt-in is per controller and survives an app restart', () async {
      FlutterSecureStorage.setMockInitialValues({
        'selected_controller_id': 'nibe_modbus',
        'beta_write_enabled_nibe_modbus': 'true',
      });
      final provider = ECLProvider(
        logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
        licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
        autoLoadDatabase: false,
      );
      for (var i = 0; i < 50 && provider.selectedControllerId != 'nibe_modbus'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(provider.selectedControllerId, 'nibe_modbus');
      expect(provider.betaWritesEnabled, isTrue);

      await provider.setSelectedController('vaillant_ebusd');
      expect(provider.betaWritesEnabled, isFalse);
    });

    test('Danfoss is verified and never gated; simulation is never gated', () async {
      final provider = ECLProvider(
        logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
        licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
        autoLoadDatabase: false,
      );
      expect(provider.isBetaController, isFalse);

      await provider.setSelectedController('weishaupt_wem');
      await provider.startSimulation();
      expect(provider.isBetaController, isTrue);
      expect(provider.isBetaWriteBlocked, isFalse);
      await provider.writeParameter(ECLRegisters.heatingCurveShift, 1);
      provider.disconnect();
    });
  });

  group('Readings', () {
    test('values the driver cannot read are absent, not defaulted', () async {
      final fake = FakeController(flowTemp: 41.5); // outdoor/return/shift unknown
      final provider = await providerWith(fake);

      await provider.refreshReadings();

      expect(provider.getReading(ECLRegisters.flowTemp)!.displayValue, 41.5);
      expect(provider.getReading(ECLRegisters.outdoorTemp), isNull);
      expect(provider.getReading(ECLRegisters.returnTemp), isNull);
      expect(provider.getReading(ECLRegisters.heatingCurveShift), isNull);
    });

    test('a value that disappears is removed instead of kept stale', () async {
      final fake = FakeController(flowTemp: 41.5);
      final provider = await providerWith(fake);
      await provider.refreshReadings();

      fake.flowTemp = null;
      await provider.refreshReadings();

      expect(provider.getReading(ECLRegisters.flowTemp), isNull);
    });
  });

  group('Writes', () {
    test('controller limits are enforced before anything is sent', () async {
      final fake = FakeController(shift: 0); // NIBE-style ±10
      final provider = await providerWith(fake);

      await expectLater(
        provider.writeParameter(ECLRegisters.heatingCurveShift, 12),
        throwsA(isA<ModbusCommunicationException>()),
      );
      expect(fake.writes, isEmpty);
    });

    test('unsupported parameter is rejected', () async {
      final fake = FakeController(
        caps: const HeatingCapabilities(supportsRoomTarget: false),
      );
      final provider = await providerWith(fake);

      await expectLater(
        provider.writeParameter(ECLRegisters.roomTargetTemp, 21),
        throwsA(isA<ModbusCommunicationException>()),
      );
    });

    test('write is confirmed by reading the value back', () async {
      final fake = FakeController(shift: 0);
      final provider = await providerWith(fake);

      final reading = await provider.writeParameter(ECLRegisters.heatingCurveShift, 3);

      expect(fake.writes, [3]);
      expect(reading.displayValue, 3);
    });

    test('ignored write is reported, and the UI shows the real value', () async {
      final fake = FakeController(shift: 1, ignoreWrites: true);
      final provider = await providerWith(fake);

      await expectLater(
        provider.writeParameter(ECLRegisters.heatingCurveShift, 4),
        throwsA(isA<ModbusCommunicationException>().having(
            (e) => e.message, 'message', contains('nicht übernommen'))),
      );
      expect(provider.getReading(ECLRegisters.heatingCurveShift)!.displayValue, 1);
    });

    test('write without read-back is not reported as success', () async {
      // Driver can't read the shift back at all.
      final fake = FakeController(shift: null, ignoreWrites: true);
      final provider = await providerWith(fake);

      await expectLater(
        provider.writeParameter(ECLRegisters.heatingCurveShift, 2),
        throwsA(isA<ModbusCommunicationException>().having(
            (e) => e.message, 'message', contains('nicht bestätigt'))),
      );
    });
  });

  group('TlsPolicy', () {
    test('self-signed certificates only on the home network', () {
      for (final host in ['192.168.178.20', '10.0.0.5', '172.20.1.1', '127.0.0.1',
          'fe80::1', 'fd12:3456::1', 'km200', 'ems-esp.local', 'fritz.box.fritz.box']) {
        expect(TlsPolicy.isLocalNetworkHost(host), isTrue, reason: host);
      }
      for (final host in ['api.viessmann.com', '8.8.8.8', '172.32.0.1', '2001:db8::1',
          'example.com']) {
        expect(TlsPolicy.isLocalNetworkHost(host), isFalse, reason: host);
      }
    });
  });
}
