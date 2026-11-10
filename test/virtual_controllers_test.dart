import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/controllers/danfoss_ecl_310_controller.dart';
import 'package:heizungstrainer/controllers/weishaupt_wem_controller.dart';
import 'package:heizungstrainer/controllers/nibe_modbus_controller.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/mock_heating_controller.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';

import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/device_registry.dart';

// Allow local loopback HTTP calls during tests
class _AllowLocalHttpOverrides extends HttpOverrides {}

// ─────────────────────────────────────────────────────────────────────────────
// Virtual Modbus TCP Server
// ─────────────────────────────────────────────────────────────────────────────

/// Modbus TCP slave for the tests.
///
/// - [strict]: reading or writing an address that is not in the register map
///   answers exception 02 (illegal data address), like a real device does.
///   Without it unmapped registers read as 0.
/// - [supportedFunctions]: every other function code answers exception 01
///   (illegal function). NIBE MODBUS 40 for example only knows 0x03 and 0x10.
/// - [requests] / [writes] record what the client sent, so a test can assert
///   the function code that was used.
class VirtualModbusServer {
  VirtualModbusServer({
    this.strict = false,
    this.supportedFunctions = const {3, 4, 6, 16},
  });

  final bool strict;
  final Set<int> supportedFunctions;
  final Map<int, int> holdingRegisters = {};
  final Map<int, int> inputRegisters = {};

  /// Every request received (also the rejected ones).
  final List<({int function, int address})> requests = [];

  /// Every write that was accepted.
  final List<({int function, int address, List<int> values})> writes = [];

  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSub;
  final List<Socket> _clients = [];

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _serverSub = _server!.listen((Socket socket) {
      _clients.add(socket);
      final buffer = <int>[];

      socket.listen(
        (data) {
          buffer.addAll(data);
          while (buffer.length >= 6) {
            final pduLen = (buffer[4] << 8) | buffer[5];
            final totalLen = 6 + pduLen;
            if (buffer.length < totalLen) break;

            final packet = buffer.sublist(0, totalLen);
            buffer.removeRange(0, totalLen);
            _handlePacket(socket, packet);
          }
        },
        onDone: () => _clients.remove(socket),
        onError: (_) => _clients.remove(socket),
      );
    });
  }

  static int _signed(int raw) => raw > 32767 ? raw - 65536 : raw;

  void _handlePacket(Socket socket, List<int> data) {
    if (data.length < 12) return;
    final fnCode = data[7];
    final addr = (data[8] << 8) | data[9];
    requests.add((function: fnCode, address: addr));

    // MBAP header (transaction id, protocol 0, length, unit id) + PDU.
    void reply(List<int> pdu) {
      final len = pdu.length + 1;
      socket.add(Uint8List.fromList([data[0], data[1], 0, 0, len >> 8, len & 0xFF, data[6], ...pdu]));
    }

    void exception(int code) => reply([fnCode | 0x80, code]);

    if (!supportedFunctions.contains(fnCode)) {
      exception(0x01);
      return;
    }

    if (fnCode == 3 || fnCode == 4) {
      final count = (data[10] << 8) | data[11];
      final regMap = fnCode == 3 ? holdingRegisters : inputRegisters;
      final addresses = [for (var i = 0; i < count; i++) addr + i];
      if (strict && !addresses.every(regMap.containsKey)) {
        exception(0x02);
        return;
      }
      reply([
        fnCode,
        count * 2,
        for (final a in addresses) ...[((regMap[a] ?? 0) >> 8) & 0xFF, (regMap[a] ?? 0) & 0xFF],
      ]);
    } else if (fnCode == 6) {
      if (strict && !holdingRegisters.containsKey(addr)) {
        exception(0x02);
        return;
      }
      final value = _signed((data[10] << 8) | data[11]);
      holdingRegisters[addr] = value;
      writes.add((function: fnCode, address: addr, values: [value]));
      reply(data.sublist(7, 12)); // echo
    } else if (fnCode == 16) {
      final count = (data[10] << 8) | data[11];
      final addresses = [for (var i = 0; i < count; i++) addr + i];
      if (data.length < 13 + count * 2 || data[12] != count * 2) {
        exception(0x03);
        return;
      }
      if (strict && !addresses.every(holdingRegisters.containsKey)) {
        exception(0x02);
        return;
      }
      final values = [
        for (var i = 0; i < count; i++) _signed((data[13 + i * 2] << 8) | data[14 + i * 2]),
      ];
      for (var i = 0; i < count; i++) {
        holdingRegisters[addr + i] = values[i];
      }
      writes.add((function: fnCode, address: addr, values: values));
      reply(data.sublist(7, 12)); // function, address, quantity
    } else {
      exception(0x01);
    }
  }

  Future<void> stop() async {
    for (final c in List<Socket>.from(_clients)) {
      try {
        c.destroy();
      } catch (_) {}
    }
    _clients.clear();
    await _serverSub?.cancel();
    await _server?.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests Entry Point
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowLocalHttpOverrides();
  FlutterSecureStorage.setMockInitialValues({});

  group('1. Danfoss ECL 310 Virtual Controller Tests (Modbus TCP)', () {
    late VirtualModbusServer virtualDanfoss;

    setUp(() async {
      virtualDanfoss = VirtualModbusServer();
      // ECL 310 register map (scale 0.01 for sensors, 1.0 for shift, 0.1 for room target):
      // 10200: Outdoor temp = 550 (5.5 °C)
      // 10203: Flow temp = 4850 (48.5 °C)
      // 10202: Return temp = 3900 (39.0 °C)
      // 10205: Hot water temp = 5200 (52.0 °C)
      // 11175 (PNU 11176 Verschieben): Shift = 0
      // 11179 (PNU 11180 Komfort-Raumsollwert): 210 = 21.0 °C
      virtualDanfoss.holdingRegisters[10200] = 550;
      virtualDanfoss.holdingRegisters[10203] = 4850;
      virtualDanfoss.holdingRegisters[10202] = 3900;
      virtualDanfoss.holdingRegisters[10205] = 5200;
      virtualDanfoss.holdingRegisters[11175] = 0;
      virtualDanfoss.holdingRegisters[11179] = 210;
      await virtualDanfoss.start();
    });

    tearDown(() async {
      await virtualDanfoss.stop();
    });

    test('connects, reads telemetry, writes shift & target, handles disconnect', () async {
      final controller = DanfossEcl310Controller();
      expect(controller.isConnected, isFalse);

      await controller.connect(host: '127.0.0.1', port: virtualDanfoss.port);
      expect(controller.isConnected, isTrue);

      // Read telemetry
      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 5.5);
      expect(telemetry.flowTemp, 48.5);
      expect(telemetry.returnTemp, 39.0);
      expect(telemetry.hotWaterTemp, 52.0);
      expect(telemetry.heatingCurveShift, 0.0);
      expect(telemetry.roomTarget, 21.0);
      expect(telemetry.spread, closeTo(9.5, 0.01));
      expect(telemetry.isOutdoorDisconnected, isFalse);

      // Set Heating Curve Shift to -2.0 K -> register 11175 = -2
      await controller.setHeatingCurveShift(-2.0);
      expect(virtualDanfoss.holdingRegisters[11175], -2);

      // Set Room Target to 22.5 °C -> register 11179 = 225
      await controller.setRoomTarget(22.5);
      expect(virtualDanfoss.holdingRegisters[11179], 225);

      // Re-read telemetry to confirm updated values
      final updated = await controller.readTelemetry();
      expect(updated.heatingCurveShift, -2.0);
      expect(updated.roomTarget, 22.5);

      // Verify sensor disconnect code (19200)
      virtualDanfoss.holdingRegisters[10200] = 19200;
      final errorTelemetry = await controller.readTelemetry();
      expect(errorTelemetry.outdoorTemp, isNull);
      expect(errorTelemetry.isOutdoorDisconnected, isTrue);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });
  });

  // Groups 2–4 (Viessmann, Bosch/Buderus, Vaillant) are not Modbus devices.
  // Their protocol tests, with mock servers that imitate vcontrold, the ViCare
  // API, EMS-ESP, KM200 and ebusd, live in viessmann_controller_test.dart,
  // bosch_buderus_ems_controller_test.dart and vaillant_ebusd_controller_test.dart.

  final throwsModbusError = throwsA(isA<ModbusCommunicationException>());

  group('5. Weishaupt heat pump Virtual Controller Tests (Modbus TCP)', () {
    late VirtualModbusServer virtualWeishaupt;

    setUp(() async {
      virtualWeishaupt = VirtualModbusServer(strict: true);
      await virtualWeishaupt.start();
    });

    tearDown(() async {
      await virtualWeishaupt.stop();
    });

    WeishauptWemController controllerFor(VirtualModbusServer server) => WeishauptWemController(
          config: WeishauptWemConfig(host: '127.0.0.1', port: server.port),
        );

    test('reads the sensors as input registers and writes the room setpoint to holding 41105', () async {
      virtualWeishaupt.inputRegisters[30001] = 38; // outdoor 3.8 °C
      virtualWeishaupt.inputRegisters[31105] = 460; // heating circuit flow 46.0 °C
      virtualWeishaupt.inputRegisters[33105] = 370; // return 37.0 °C
      virtualWeishaupt.inputRegisters[32102] = 525; // hot water 52.5 °C
      virtualWeishaupt.holdingRegisters[41105] = 210; // room setpoint comfort 21.0 °C

      final controller = controllerFor(virtualWeishaupt);
      await controller.connect(host: '127.0.0.1', port: virtualWeishaupt.port);
      expect(controller.isConnected, isTrue);
      virtualWeishaupt.requests.clear(); // connect() already read once

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 3.8);
      expect(telemetry.flowTemp, 46.0);
      expect(telemetry.returnTemp, 37.0);
      expect(telemetry.hotWaterTemp, 52.5);
      expect(telemetry.roomTarget, 21.0);
      expect(telemetry.heatingCurveShift, isNull);
      expect(telemetry.spread, 9.0);

      // Sensors with FC04, the setpoint with FC03.
      expect(virtualWeishaupt.requests, [
        (function: 4, address: 30001),
        (function: 4, address: 31105),
        (function: 4, address: 33105),
        (function: 4, address: 32102),
        (function: 3, address: 41105),
      ]);

      await controller.setRoomTarget(22.5);
      expect(virtualWeishaupt.holdingRegisters[41105], 225);
      expect((await controller.readTelemetry()).roomTarget, 22.5);

      // No parallel shift over Modbus: nothing may be written.
      expect(controller.capabilities.supportsHeatingCurveShift, isFalse);
      await expectLater(controller.setHeatingCurveShift(-2.0), throwsModbusError);
      expect(virtualWeishaupt.writes.map((w) => w.address), [41105]);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });

    test('a device that answers none of the sensor registers is an error, not "all values empty"', () async {
      // Only the invented <= 1.2.10 map exists on this device.
      for (final address in [3101, 3102, 3103, 3104, 3105, 3106]) {
        virtualWeishaupt.holdingRegisters[address] = 100;
      }
      final controller = controllerFor(virtualWeishaupt);
      // Whether connect() already notices or only the first read: it must throw.
      Future<void> connectAndRead() async {
        await controller.connect(host: '127.0.0.1', port: virtualWeishaupt.port);
        await controller.readTelemetry();
      }

      await expectLater(connectAndRead(), throwsModbusError);

      final probe = await WeishauptWemController.testConnection(
        WeishauptWemConfig(host: '127.0.0.1', port: virtualWeishaupt.port),
      );
      expect(probe['success'], isFalse);
      await controller.disconnect();
    });
  });

  group('6. NIBE Modbus Virtual Controller Tests (S-Serie & MODBUS 40)', () {
    test('S-Series: sensors are input registers 1/5/7/8, offset is holding 30, holding 26 is never written',
        () async {
      final nibe = VirtualModbusServer(strict: true);
      addTearDown(nibe.stop);
      nibe.inputRegisters[1] = 42; // BT1 outdoor 4.2 °C
      nibe.inputRegisters[5] = 445; // BT2 flow 44.5 °C
      nibe.inputRegisters[7] = 360; // BT3 return 36.0 °C
      nibe.inputRegisters[8] = 510; // BT7 hot water 51.0 °C
      nibe.holdingRegisters[26] = 7; // heating curve NUMBER – not a room setpoint
      nibe.holdingRegisters[30] = 0; // curve offset, whole steps
      await nibe.start();

      final controller = NibeModbusController(
        config: NibeModbusConfig(host: '127.0.0.1', port: nibe.port),
      );
      await controller.connect(host: '127.0.0.1', port: nibe.port);
      expect(controller.isConnected, isTrue);
      nibe.requests.clear(); // connect() already read once

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 4.2);
      expect(telemetry.flowTemp, 44.5);
      expect(telemetry.returnTemp, 36.0);
      expect(telemetry.hotWaterTemp, 51.0);
      expect(telemetry.roomTarget, isNull);
      expect(telemetry.heatingCurveShift, 0.0);
      expect(telemetry.spread, closeTo(8.5, 0.01));
      expect(nibe.requests, [
        (function: 4, address: 1),
        (function: 4, address: 5),
        (function: 4, address: 7),
        (function: 4, address: 8),
        (function: 3, address: 30),
      ]);

      await controller.setHeatingCurveShift(2.0);
      expect(nibe.holdingRegisters[30], 2); // whole steps, not tenths
      await controller.setHeatingCurveShift(-3.0);
      expect(nibe.holdingRegisters[30], -3);
      expect((await controller.readTelemetry()).heatingCurveShift, -3.0);
      expect(nibe.writes.map((w) => w.function).toSet(), {6}); // S series: write single

      // There is no room setpoint register: setRoomTarget must not write anything.
      expect(controller.capabilities.supportsRoomTarget, isFalse);
      await expectLater(controller.setRoomTarget(21.5), throwsModbusError);
      expect(nibe.holdingRegisters[26], 7);
      expect(nibe.requests.where((r) => r.address == 26), isEmpty);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });

    for (final presetId in ['nibe_f_series_modbus40', 'nibe_smo40']) {
      test('$presetId: holding 40004…, offset 47011, written with FC 0x10', () async {
        // MODBUS 40 implements only "read holding" and "write multiple".
        final nibe = VirtualModbusServer(strict: true, supportedFunctions: const {3, 16});
        addTearDown(nibe.stop);
        nibe.holdingRegisters[40004] = 25; // 2.5 °C outdoor
        nibe.holdingRegisters[40008] = 450; // 45.0 °C flow
        nibe.holdingRegisters[40012] = 365; // 36.5 °C return
        nibe.holdingRegisters[40013] = 520; // 52.0 °C hot water
        nibe.holdingRegisters[47011] = -1; // Heat Offset S1
        nibe.holdingRegisters[47007] = 9; // heating curve slope: never touched
        await nibe.start();

        final preset = NibeModbusConfig.presets.firstWhere((p) => p.id == presetId);
        final config = NibeModbusConfig.fromPreset(preset).copyWith(host: '127.0.0.1', port: nibe.port);
        expect(config.writeMultiple, isTrue);

        final controller = NibeModbusController(config: config);
        await controller.connect(host: '127.0.0.1', port: nibe.port);

        final telemetry = await controller.readTelemetry();
        expect(telemetry.outdoorTemp, 2.5);
        expect(telemetry.flowTemp, 45.0);
        expect(telemetry.returnTemp, 36.5);
        expect(telemetry.hotWaterTemp, 52.0);
        expect(telemetry.roomTarget, isNull);
        expect(telemetry.heatingCurveShift, -1.0);

        await controller.setHeatingCurveShift(2.0);
        await controller.setHeatingCurveShift(-4.0);
        expect(nibe.writes.map((w) => (w.function, w.address, w.values.single)), [
          (16, 47011, 2),
          (16, 47011, -4),
        ]);
        expect(nibe.holdingRegisters[47011], -4);
        expect(nibe.holdingRegisters[47007], 9); // slope unchanged
        expect(nibe.requests.map((r) => r.function).toSet(), {3, 16});

        await controller.disconnect();
      });
    }

    test('S-Series preset against a device without those input registers throws', () async {
      final nibe = VirtualModbusServer(strict: true);
      addTearDown(nibe.stop);
      // The <= 1.2.10 assumption: sensors as HOLDING registers.
      for (final address in [1, 5, 7, 8]) {
        nibe.holdingRegisters[address] = 100;
      }
      nibe.holdingRegisters[30] = 0;
      await nibe.start();

      final controller = NibeModbusController(
        config: NibeModbusConfig(host: '127.0.0.1', port: nibe.port),
      );
      // Whether connect() already notices or only the first read: it must throw.
      Future<void> connectAndRead() async {
        await controller.connect(host: '127.0.0.1', port: nibe.port);
        await controller.readTelemetry();
      }

      await expectLater(connectAndRead(), throwsModbusError);
      await controller.disconnect();
    });
  });

  group('7. Generisch Modbus TCP Virtual Controller Tests (Stiebel ISG & Custom)', () {
    late VirtualModbusServer virtualGeneric;

    setUp(() async {
      virtualGeneric = VirtualModbusServer(strict: true);
      await virtualGeneric.start();
    });

    tearDown(() async {
      await virtualGeneric.stop();
    });

    test('Stiebel Eltron ISG: input registers 506/514/515/521, comfort temperature holding 1501', () async {
      virtualGeneric.inputRegisters[506] = 75; // 7.5 °C outdoor
      virtualGeneric.inputRegisters[514] = 480; // 48.0 °C flow
      virtualGeneric.inputRegisters[515] = 390; // 39.0 °C return
      virtualGeneric.inputRegisters[521] = -32768; // 0x8000 = no DHW sensor
      virtualGeneric.holdingRegisters[1501] = 215; // 21.5 °C comfort temperature HK1

      final preset = GenericModbusConfig.presets.firstWhere((p) => p.id == 'stiebel_isg');
      final config = GenericModbusConfig.fromPreset(preset).copyWith(
        host: '127.0.0.1',
        port: virtualGeneric.port,
      );

      final controller = GenericModbusController(config: config);
      await controller.connect(host: '127.0.0.1', port: virtualGeneric.port);
      expect(controller.isConnected, isTrue);

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 7.5);
      expect(telemetry.flowTemp, 48.0);
      expect(telemetry.returnTemp, 39.0);
      expect(telemetry.hotWaterTemp, isNull);
      expect(telemetry.roomTarget, 21.5);
      expect(telemetry.heatingCurveShift, isNull);
      expect(telemetry.spread, 9.0);
      expect(virtualGeneric.requests.toSet(), {
        (function: 4, address: 506),
        (function: 4, address: 514),
        (function: 4, address: 515),
        (function: 4, address: 521),
        (function: 3, address: 1501),
      });

      await controller.setRoomTarget(22.0);
      expect(virtualGeneric.holdingRegisters[1501], 220);
      // The read after a write must show the new value (no stale throttle cache).
      expect((await controller.readTelemetry()).roomTarget, 22.0);

      // The ISG has no parallel-shift register (1504 is the curve rise).
      expect(controller.capabilities.supportsHeatingCurveShift, isFalse);
      await expectLater(controller.setHeatingCurveShift(-1.0), throwsModbusError);
      expect(virtualGeneric.writes.map((w) => w.address), [1501]);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });

    test('default config reads holding 1–4 and offers no writes', () async {
      virtualGeneric.holdingRegisters.addAll({1: -25, 2: 401, 3: 322, 4: 550});
      final controller = GenericModbusController(
        config: GenericModbusConfig(host: '127.0.0.1', port: virtualGeneric.port),
      );
      await controller.connect(host: '127.0.0.1', port: virtualGeneric.port);
      final t = await controller.readTelemetry();
      expect(t.outdoorTemp, -2.5);
      expect(t.flowTemp, 40.1);
      expect(t.returnTemp, 32.2);
      expect(t.hotWaterTemp, 55.0);
      expect(t.roomTarget, isNull);
      expect(t.heatingCurveShift, isNull);
      await expectLater(controller.setRoomTarget(21.0), throwsModbusError);
      await expectLater(controller.setHeatingCurveShift(1.0), throwsModbusError);
      expect(virtualGeneric.writes, isEmpty);
      await controller.disconnect();
    });

    test('connect fails when none of the configured registers exists', () async {
      // Device has registers, just not the configured ones → exception 02 each.
      virtualGeneric.holdingRegisters[100] = 1;
      final config = GenericModbusConfig(host: '127.0.0.1', port: virtualGeneric.port);
      final controller = GenericModbusController(config: config);

      await expectLater(
        controller.connect(host: '127.0.0.1', port: virtualGeneric.port),
        throwsModbusError,
      );
      expect(controller.isConnected, isFalse);
      expect(virtualGeneric.requests, hasLength(4));

      final probe = await GenericModbusController.testConnection(config);
      expect(probe['success'], isFalse);
    });

    test('connect fails when the device rejects every function code', () async {
      final deaf = VirtualModbusServer(supportedFunctions: const {});
      addTearDown(deaf.stop);
      await deaf.start();
      final controller = GenericModbusController(
        config: GenericModbusConfig(host: '127.0.0.1', port: deaf.port),
      );
      await expectLater(controller.connect(host: '127.0.0.1', port: deaf.port), throwsModbusError);
      expect(controller.isConnected, isFalse);
    });
  });
  group('7b. Samson TROVIS 557x (generic Modbus preset, read-only)', () {
    late VirtualModbusServer trovis;
    setUp(() async {
      trovis = VirtualModbusServer(strict: true);
      await trovis.start();
    });
    tearDown(() async => trovis.stop());

    test('reads AF1/VF1/RüF1/SF1 (HR 40010/40013/40017/40023) and offers no writes', () async {
      trovis.holdingRegisters[9] = -32; // AF1 −3.2 °C
      trovis.holdingRegisters[12] = 512; // VF1 51.2 °C
      trovis.holdingRegisters[16] = 418; // RüF1 41.8 °C
      trovis.holdingRegisters[22] = 553; // SF1 55.3 °C
      final preset = GenericModbusConfig.presets.firstWhere((p) => p.id == 'samson_trovis');
      final config = GenericModbusConfig.fromPreset(preset).copyWith(host: '127.0.0.1', port: trovis.port);
      final controller = GenericModbusController(config: config);
      await controller.connect(host: '127.0.0.1', port: trovis.port);
      final t = await controller.readTelemetry();
      expect(t.outdoorTemp, closeTo(-3.2, 0.001));
      expect(t.flowTemp, closeTo(51.2, 0.001));
      expect(t.returnTemp, closeTo(41.8, 0.001));
      expect(t.hotWaterTemp, closeTo(55.3, 0.001));
      expect(t.roomTarget, isNull);
      expect(controller.capabilities.supportsRoomTarget, isFalse);
      expect(controller.capabilities.supportsHeatingCurveShift, isFalse);
      await controller.disconnect();
    });
  });

  group('8. Mock Heating Controller Simulation Tests', () {
    test('simulates live responses, updates shift and room target', () async {
      final mock = MockHeatingController(
        id: 'virtual_sim_brand',
        brandName: 'Virtual Test Brand',
        modelName: 'VT-100',
      );

      expect(mock.isConnected, isFalse);
      await mock.connect(host: 'localhost');
      expect(mock.isConnected, isTrue);

      final t1 = await mock.readTelemetry();
      expect(t1.flowTemp, 46.0);
      expect(t1.returnTemp, 36.0);
      expect(t1.outdoorTemp, 7.5);

      await mock.setHeatingCurveShift(3.0);
      final t2 = await mock.readTelemetry();
      expect(t2.heatingCurveShift, 3.0);
      expect(t2.flowTemp, 49.0); // 46.0 + 3.0

      await mock.setRoomTarget(23.5);
      final t3 = await mock.readTelemetry();
      expect(t3.roomTarget, 23.5);

      await mock.disconnect();
      expect(mock.isConnected, isFalse);
    });
  });

  group('9. ECLProvider End-to-End Virtual Simulation across ALL Known Controllers', () {
    test('switches dynamically between all 7 controllers and runs simulation mode', () async {
      final provider = ECLProvider(autoLoadDatabase: false);
      final knownControllers = DeviceRegistry.knownControllers;

      expect(knownControllers.length, 7);

      for (final desc in knownControllers) {
        // 1. Select controller
        await provider.setSelectedController(desc.id);
        expect(provider.selectedControllerId, desc.id);
        expect(provider.currentControllerDescriptor.brand, desc.brand);

        // 2. Start simulation
        await provider.startSimulation();
        expect(provider.isConnected, isTrue);
        expect(provider.controllerIp, contains('Simulation'));

        // 3. Telemetry assertions
        expect(provider.hasCachedReadings, isTrue);
        final outdoor = provider.getReading(ECLRegisters.outdoorTemp);
        final flow = provider.getReading(ECLRegisters.flowTemp);
        final ret = provider.getReading(ECLRegisters.returnTemp);

        expect(outdoor, isNotNull);
        expect(flow, isNotNull);
        expect(ret, isNotNull);
        expect(outdoor!.displayValue, 7.5);
        expect(flow!.displayValue, 46.0);
        expect(ret!.displayValue, 36.0);

        // 4. Test simulated parameter write (shift is integer degrees on ECL)
        await provider.writeParameter(ECLRegisters.heatingCurveShift, 2.0);
        final shift = provider.getReading(ECLRegisters.heatingCurveShift);
        expect(shift, isNotNull);
        expect(shift!.displayValue, 2.0);

        // Also test room target write
        await provider.writeParameter(ECLRegisters.roomTargetTemp, 22.5);
        final target = provider.getReading(ECLRegisters.roomTargetTemp);
        expect(target, isNotNull);
        expect(target!.displayValue, 22.5);

        // 5. Clean disconnect before next brand
        provider.disconnect();
        expect(provider.isConnected, isFalse);
      }
    });
  });
}
