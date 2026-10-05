import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/controllers/danfoss_ecl_310_controller.dart';
import 'package:heizungstrainer/controllers/viessmann_controller.dart';
import 'package:heizungstrainer/controllers/bosch_buderus_ems_controller.dart';
import 'package:heizungstrainer/controllers/vaillant_ebusd_controller.dart';
import 'package:heizungstrainer/controllers/weishaupt_wem_controller.dart';
import 'package:heizungstrainer/controllers/nibe_modbus_controller.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/mock_heating_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/device_registry.dart';

// Allow local loopback HTTP calls during tests
class _AllowLocalHttpOverrides extends HttpOverrides {}

// ─────────────────────────────────────────────────────────────────────────────
// Virtual Modbus TCP Server
// ─────────────────────────────────────────────────────────────────────────────

class VirtualModbusServer {
  final Map<int, int> holdingRegisters = {};
  final Map<int, int> inputRegisters = {};
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

  void _handlePacket(Socket socket, List<int> data) {
    if (data.length < 8) return;
    final txIdHi = data[0];
    final txIdLo = data[1];
    final unitId = data[6];
    final fnCode = data[7];

    if (fnCode == 3 || fnCode == 4) {
      final addr = (data[8] << 8) | data[9];
      final count = (data[10] << 8) | data[11];
      final regMap = fnCode == 3 ? holdingRegisters : inputRegisters;

      final byteCount = count * 2;
      final respLen = 1 + 1 + 1 + byteCount;
      final resp = Uint8List(6 + respLen);
      resp[0] = txIdHi;
      resp[1] = txIdLo;
      resp[2] = 0;
      resp[3] = 0;
      resp[4] = (respLen >> 8) & 0xFF;
      resp[5] = respLen & 0xFF;
      resp[6] = unitId;
      resp[7] = fnCode;
      resp[8] = byteCount;

      for (int i = 0; i < count; i++) {
        final val = (regMap[addr + i] ?? 0) & 0xFFFF;
        resp[9 + i * 2] = (val >> 8) & 0xFF;
        resp[10 + i * 2] = val & 0xFF;
      }
      socket.add(resp);
    } else if (fnCode == 6) {
      final addr = (data[8] << 8) | data[9];
      final rawVal = (data[10] << 8) | data[11];
      final val = rawVal > 32767 ? rawVal - 65536 : rawVal;
      holdingRegisters[addr] = val;
      socket.add(Uint8List.fromList(data));
    } else if (fnCode == 16) {
      final addr = (data[8] << 8) | data[9];
      final count = (data[10] << 8) | data[11];
      for (int i = 0; i < count; i++) {
        final rawVal = (data[13 + i * 2] << 8) | data[14 + i * 2];
        final val = rawVal > 32767 ? rawVal - 65536 : rawVal;
        holdingRegisters[addr + i] = val;
      }
      final resp = Uint8List(12);
      resp[0] = txIdHi;
      resp[1] = txIdLo;
      resp[2] = 0;
      resp[3] = 0;
      resp[4] = 0;
      resp[5] = 6;
      resp[6] = unitId;
      resp[7] = fnCode;
      resp[8] = data[8];
      resp[9] = data[9];
      resp[10] = data[10];
      resp[11] = data[11];
      socket.add(resp);
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

  group('2. Viessmann Virtual Controller Tests (Optolink TCP)', () {
    test('Optolink TCP: connects to mock vcontrold, reads & writes setpoints', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      double target = 20.5;
      double niveau = 1.0;

      final serverSub = server.listen((Socket client) {
        client.listen((data) {
          final cmd = utf8.decode(data).trim();
          if (cmd == 'getTempA') {
            client.write('4.2 Grad C\nvctrld>');
          } else if (cmd == 'getTempVl') {
            client.write('46.8 Grad C\nvctrld>');
          } else if (cmd == 'getTempRl') {
            client.write('37.5 Grad C\nvctrld>');
          } else if (cmd == 'getTempWWist') {
            client.write('53.0 Grad C\nvctrld>');
          } else if (cmd == 'getTempRaumSoll') {
            client.write('$target Grad C\nvctrld>');
          } else if (cmd == 'getNiveau') {
            client.write('$niveau K\nvctrld>');
          } else if (cmd.startsWith('setTempRaumSoll')) {
            final parts = cmd.split(' ');
            if (parts.length >= 2) target = double.tryParse(parts[1]) ?? target;
            client.write('OK\nvctrld>');
          } else if (cmd.startsWith('setNiveau')) {
            final parts = cmd.split(' ');
            if (parts.length >= 2) niveau = double.tryParse(parts[1]) ?? niveau;
            client.write('OK\nvctrld>');
          } else {
            client.write('vctrld>');
          }
        });
      });

      try {
        final config = ViessmannConfig(
          connectionType: ViessmannConnectionType.optolinkTcp,
          host: '127.0.0.1',
          port: port,
          circuit: '0',
          timeoutSeconds: 2,
        );

        final controller = ViessmannController(config: config);
        await controller.connect(host: '127.0.0.1', port: port);
        expect(controller.isConnected, isTrue);

        final telemetry = await controller.readTelemetry();
        expect(telemetry.outdoorTemp, 4.2);
        expect(telemetry.flowTemp, 46.8);
        expect(telemetry.returnTemp, 37.5);
        expect(telemetry.hotWaterTemp, 53.0);
        expect(telemetry.roomTarget, 20.5);
        expect(telemetry.heatingCurveShift, 1.0);
        expect(telemetry.spread, closeTo(9.3, 0.01));

        // Write room target & niveau
        await controller.setRoomTarget(22.0);
        expect(target, 22.0);

        await controller.setHeatingCurveShift(2.0);
        expect(niveau, 2.0);

        await controller.disconnect();
        expect(controller.isConnected, isFalse);
      } finally {
        await serverSub.cancel();
        await server.close();
      }
    });
  });

  group('3. Bosch & Buderus Virtual Controller Tests (EMS-ESP REST & KM200 AES)', () {
    test('EMS-ESP REST: connects to mock gateway, reads telemetry, writes setpoints', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      double target = 21.0;
      double offset = 0.0;

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        final method = request.method;

        if (method == 'GET' && path == '/api/system') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'version': '3.6.5', 'status': 'connected'}));
          await request.response.close();
        } else if (method == 'GET' && path == '/api/boiler') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'curflowtemp': 47.0,
              'rettemp': 38.0,
              'outdoortemp': 5.0,
              'wwcurtemp': 52.0,
            }));
          await request.response.close();
        } else if (method == 'GET' && path == '/api/thermostat') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'hc1': {'seltemp': target, 'offset': offset, 'currtemp': 21.1}
            }));
          await request.response.close();
        } else if (method == 'POST' && path.startsWith('/api/thermostat')) {
          final body = await utf8.decodeStream(request);
          final map = jsonDecode(body) as Map<String, dynamic>;
          if (map['cmd'] == 'seltemp' || map.containsKey('value')) {
            target = ((map['data'] ?? map['value']) as num).toDouble();
          }
          if (map['cmd'] == 'offset' || path.endsWith('/offset')) {
            offset = ((map['data'] ?? map['value']) as num).toDouble();
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'ok'}));
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      try {
        final config = BoschBuderusEmsConfig(
          host: '127.0.0.1',
          port: port,
          circuit: 'hc1',
          timeoutSeconds: 2,
        );

        final controller = BoschBuderusEmsController(config: config);
        await controller.connect(host: '127.0.0.1', port: port);
        expect(controller.isConnected, isTrue);

        final telemetry = await controller.readTelemetry();
        expect(telemetry.flowTemp, 47.0);
        expect(telemetry.returnTemp, 38.0);
        expect(telemetry.outdoorTemp, 5.0);
        expect(telemetry.hotWaterTemp, 52.0);
        expect(telemetry.roomTarget, 21.0);
        expect(telemetry.spread, 9.0);

        await controller.setRoomTarget(22.0);
        expect(target, 22.0);

        await controller.setHeatingCurveShift(1.5);
        expect(offset, 1.5);

        await controller.disconnect();
        expect(controller.isConnected, isFalse);
      } finally {
        await server.close(force: true);
      }
    });

    test('KM200: handles AES-128 encrypted payloads from virtual gateway', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      const hexKey = '0123456789abcdef0123456789abcdef';
      final keyBytes = Uint8List.fromList(
        List.generate(16, (i) => int.parse(hexKey.substring(i * 2, i * 2 + 2), radix: 16)),
      );
      final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.ecb, padding: 'PKCS7'));

      String encryptJson(Map<String, dynamic> data) {
        final plain = jsonEncode(data);
        return encrypter.encrypt(plain).base64;
      }

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (path == '/gateway/versionFirmware') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set('Content-Type', 'application/json')
            ..write(encryptJson({'id': '/gateway/versionFirmware', 'value': '04.06.07'}));
          await request.response.close();
        } else if (path == '/system/sensors/temperatures/outdoor_t1') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set('Content-Type', 'application/json')
            ..write(encryptJson({'id': path, 'value': 4.5}));
          await request.response.close();
        } else if (path == '/heatingCircuits/hc1/actualSupplyTemperature') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set('Content-Type', 'application/json')
            ..write(encryptJson({'id': path, 'value': 48.0}));
          await request.response.close();
        } else if (path == '/heatingCircuits/hc1/temperatureRoomManual') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set('Content-Type', 'application/json')
            ..write(encryptJson({'id': path, 'value': 21.0}));
          await request.response.close();
        } else if (path == '/heatingCircuits/hc1/roomTemperatureHeatingCurveOffset') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set('Content-Type', 'application/json')
            ..write(encryptJson({'id': path, 'value': 0.0}));
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set('Content-Type', 'application/json')
            ..write(encryptJson({'id': path, 'value': 0.0}));
          await request.response.close();
        }
      });

      try {
        final config = BoschBuderusEmsConfig(
          gatewayType: BoschGatewayType.km200,
          host: '127.0.0.1',
          port: port,
          km200Key: hexKey,
          circuit: 'hc1',
          timeoutSeconds: 2,
        );

        final controller = BoschBuderusEmsController(config: config);
        await controller.connect(host: '127.0.0.1', port: port);
        expect(controller.isConnected, isTrue);

        final telemetry = await controller.readTelemetry();
        expect(telemetry.outdoorTemp, 4.5);
        expect(telemetry.flowTemp, 48.0);
        expect(telemetry.roomTarget, 21.0);

        await controller.disconnect();
        expect(controller.isConnected, isFalse);
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('4. Vaillant eBUS / eBUSd Virtual Controller Tests (HTTP JSON)', () {
    test('connects to mock eBUSd, parses multi-circuit JSON, writes setpoints', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      double target = 21.0;
      double shift = 0.0;

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        final method = request.method;

        if (method == 'GET' && path == '/data') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'bai': {
                'messages': {
                  'flowtemp': {'value': 47.3},
                  'returntemp': {'value': 38.1},
                  'outdoortemp': {'value': 5.8},
                  'storagetemp': {'value': 51.0},
                }
              },
              '700': {
                'messages': {
                  'desiredroomtemp': {'value': target},
                  'parallelshift': {'value': shift},
                }
              }
            }));
          await request.response.close();
        } else if (method == 'GET' && path.startsWith('/data/')) {
          final valStr = request.uri.queryParameters['value'];
          if (valStr != null) {
            final parsedVal = double.tryParse(valStr);
            if (parsedVal != null) {
              if (path.contains('DesiredRoomTemp') || path.contains('room')) {
                target = parsedVal;
              } else if (path.contains('ParallelShift') || path.contains('shift')) {
                shift = parsedVal;
              }
            }
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'ok'}));
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      try {
        final config = VaillantEbusdConfig(
          host: '127.0.0.1',
          port: port,
          circuit: 'bai',
          timeoutSeconds: 2,
        );

        final controller = VaillantEbusdController(config: config);
        await controller.connect(host: '127.0.0.1', port: port);
        expect(controller.isConnected, isTrue);

        final telemetry = await controller.readTelemetry();
        expect(telemetry.flowTemp, 47.3);
        expect(telemetry.returnTemp, 38.1);
        expect(telemetry.outdoorTemp, 5.8);
        expect(telemetry.hotWaterTemp, 51.0);
        expect(telemetry.roomTarget, 21.0);
        expect(telemetry.heatingCurveShift, 0.0);
        expect(telemetry.spread, closeTo(9.2, 0.01));

        await controller.setRoomTarget(22.5);
        expect(target, 22.5);

        await controller.setHeatingCurveShift(-1.0);
        expect(shift, -1.0);

        await controller.disconnect();
        expect(controller.isConnected, isFalse);
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('5. Weishaupt WEM Virtual Controller Tests (Modbus TCP)', () {
    late VirtualModbusServer virtualWeishaupt;

    setUp(() async {
      virtualWeishaupt = VirtualModbusServer();
      // Weishaupt WEM standard registers:
      // 3101: Outdoor temp = 38 (3.8 °C)
      // 3102: Flow temp = 460 (46.0 °C)
      // 3103: Return temp = 370 (37.0 °C)
      // 3104: Hot water temp = 525 (52.5 °C)
      // 3105: Room target = 210 (21.0 °C)
      // 3106: Shift = 10 (1.0)
      virtualWeishaupt.holdingRegisters[3101] = 38;
      virtualWeishaupt.holdingRegisters[3102] = 460;
      virtualWeishaupt.holdingRegisters[3103] = 370;
      virtualWeishaupt.holdingRegisters[3104] = 525;
      virtualWeishaupt.holdingRegisters[3105] = 210;
      virtualWeishaupt.holdingRegisters[3106] = 10;
      await virtualWeishaupt.start();
    });

    tearDown(() async {
      await virtualWeishaupt.stop();
    });

    test('connects, reads Weishaupt telemetry, writes shift & room target', () async {
      final config = WeishauptWemConfig(
        host: '127.0.0.1',
        port: virtualWeishaupt.port,
      );

      final controller = WeishauptWemController(config: config);
      await controller.connect(host: '127.0.0.1', port: virtualWeishaupt.port);
      expect(controller.isConnected, isTrue);

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 3.8);
      expect(telemetry.flowTemp, 46.0);
      expect(telemetry.returnTemp, 37.0);
      expect(telemetry.hotWaterTemp, 52.5);
      expect(telemetry.roomTarget, 21.0);
      expect(telemetry.heatingCurveShift, 1.0);
      expect(telemetry.spread, 9.0);

      // Write shift (-2.0) -> register 3106 = -20
      await controller.setHeatingCurveShift(-2.0);
      expect(virtualWeishaupt.holdingRegisters[3106], -20);

      // Write room target (22.5) -> register 3105 = 225
      await controller.setRoomTarget(22.5);
      expect(virtualWeishaupt.holdingRegisters[3105], 225);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });
  });

  group('6. NIBE Modbus Virtual Controller Tests (S-Serie & F-Serie)', () {
    late VirtualModbusServer virtualNibe;

    setUp(() async {
      virtualNibe = VirtualModbusServer();
      await virtualNibe.start();
    });

    tearDown(() async {
      await virtualNibe.stop();
    });

    test('S-Series: reads registers (1, 5, 7, 8, 26, 30) and writes setpoints', () async {
      virtualNibe.holdingRegisters[1] = 42; // 4.2 °C outdoor
      virtualNibe.holdingRegisters[5] = 445; // 44.5 °C flow
      virtualNibe.holdingRegisters[7] = 360; // 36.0 °C return
      virtualNibe.holdingRegisters[8] = 510; // 51.0 °C hot water
      virtualNibe.holdingRegisters[26] = 205; // 20.5 °C room target
      virtualNibe.holdingRegisters[30] = 0; // offset 0 (whole steps, unscaled)

      final config = NibeModbusConfig(
        host: '127.0.0.1',
        port: virtualNibe.port,
      );

      final controller = NibeModbusController(config: config);
      await controller.connect(host: '127.0.0.1', port: virtualNibe.port);
      expect(controller.isConnected, isTrue);

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 4.2);
      expect(telemetry.flowTemp, 44.5);
      expect(telemetry.returnTemp, 36.0);
      expect(telemetry.hotWaterTemp, 51.0);
      expect(telemetry.roomTarget, 20.5);
      expect(telemetry.heatingCurveShift, 0.0);
      expect(telemetry.spread, closeTo(8.5, 0.01));

      // Write shift & room target
      await controller.setHeatingCurveShift(2.0);
      expect(virtualNibe.holdingRegisters[30], 2); // offset steps, not tenths

      await controller.setRoomTarget(21.5);
      expect(virtualNibe.holdingRegisters[26], 215);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });

    test('F-Series (Modbus 40): reads registers 40004..47011', () async {
      virtualNibe.holdingRegisters[40004] = 25; // 2.5 °C outdoor
      virtualNibe.holdingRegisters[40008] = 450; // 45.0 °C flow
      virtualNibe.holdingRegisters[40012] = 365; // 36.5 °C return
      virtualNibe.holdingRegisters[40013] = 520; // 52.0 °C hot water
      virtualNibe.holdingRegisters[47011] = -1; // Heat Offset S1 = -1
      virtualNibe.holdingRegisters[47007] = 9; // heating curve slope: never touched

      final preset = NibeModbusConfig.presets.firstWhere((p) => p.id == 'nibe_f_series_modbus40');
      final config = NibeModbusConfig.fromPreset(preset).copyWith(
        host: '127.0.0.1',
        port: virtualNibe.port,
      );

      final controller = NibeModbusController(config: config);
      await controller.connect(host: '127.0.0.1', port: virtualNibe.port);
      expect(controller.isConnected, isTrue);

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 2.5);
      expect(telemetry.flowTemp, 45.0);
      expect(telemetry.returnTemp, 36.5);
      expect(telemetry.hotWaterTemp, 52.0);
      expect(telemetry.roomTarget, isNull); // room setpoint register not mapped
      expect(telemetry.heatingCurveShift, -1.0);

      await controller.setHeatingCurveShift(2.0);
      expect(virtualNibe.holdingRegisters[47011], 2);
      expect(virtualNibe.holdingRegisters[47007], 9); // slope unchanged

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });
  });

  group('7. Generisch Modbus TCP Virtual Controller Tests (Stiebel ISG & Custom)', () {
    late VirtualModbusServer virtualGeneric;

    setUp(() async {
      virtualGeneric = VirtualModbusServer();
      await virtualGeneric.start();
    });

    tearDown(() async {
      await virtualGeneric.stop();
    });

    test('Stiebel Eltron ISG profile: reads registers (501..1502) and writes setpoints', () async {
      virtualGeneric.holdingRegisters[501] = 75; // 7.5 °C outdoor
      virtualGeneric.holdingRegisters[502] = 480; // 48.0 °C flow
      virtualGeneric.holdingRegisters[503] = 390; // 39.0 °C return
      virtualGeneric.holdingRegisters[504] = 540; // 54.0 °C hot water
      virtualGeneric.holdingRegisters[1501] = 215; // 21.5 °C room target
      virtualGeneric.holdingRegisters[1502] = 5; // 0.5 shift

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
      expect(telemetry.hotWaterTemp, 54.0);
      expect(telemetry.roomTarget, 21.5);
      expect(telemetry.heatingCurveShift, 0.5);
      expect(telemetry.spread, 9.0);

      // Write shift & room target
      await controller.setHeatingCurveShift(-1.0);
      expect(virtualGeneric.holdingRegisters[1502], -10);

      await controller.setRoomTarget(22.0);
      expect(virtualGeneric.holdingRegisters[1501], 220);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
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
