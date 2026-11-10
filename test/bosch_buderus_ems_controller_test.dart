import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/controllers/bosch_buderus_ems_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

class _AllowLocalHttpOverrides extends HttpOverrides {}

/// Imitates the REST API of an EMS-ESP gateway.
///
/// Reads need no token (before 3.10); every POST needs `Bearer <token>`,
/// otherwise 401. A command the thermostat does not have answers 404.
class MockEmsEsp {
  static const token = 'ems-esp-access-token';

  /// `GET /api/boiler`. Default: EMS-ESP 3.6 (flat `wwcurtemp`).
  Map<String, dynamic> boiler = {
    'curflowtemp': 46.5,
    'rettemp': 37.2,
    'outdoortemp': 5.4,
    'wwcurtemp': 53.0,
  };

  /// Entities of heating circuit hc1 in `GET /api/thermostat`.
  Map<String, dynamic> hc1 = {'seltemp': 21, 'currtemp': 20.8, 'offsettemp': 0};

  /// Path and decoded body of every POST that was authorised.
  final List<List<Object>> posts = [];

  late final HttpServer _server;
  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _reply(HttpRequest request, int status, Object body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    final body = await utf8.decodeStream(request);

    if (request.method == 'GET') {
      if (path == '/api/system') {
        return _reply(request, 200, {
          'system': {'version': '3.7.2', 'uptime': '000+06:14:22.340'},
        });
      }
      if (path == '/api/boiler') return _reply(request, 200, boiler);
      if (path == '/api/thermostat') return _reply(request, 200, {'hc1': hc1});
      return _reply(request, 404, {'message': 'Not Found'});
    }

    if (request.method != 'POST') return _reply(request, 405, {'message': 'Method Not Allowed'});
    if (request.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $token') {
      return _reply(request, 401, {'message': 'Unauthorized'});
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    posts.add([path, json]);

    // Either {"cmd", "data", "id"} on the device, or {"value"} on the entity path.
    String? command;
    Object? data;
    if (path == '/api/thermostat' && json['id'] == 1) {
      command = json['cmd'] as String?;
      data = json['data'];
    } else if (path.startsWith('/api/thermostat/hc1/')) {
      command = path.split('/').last;
      data = json['value'];
    }
    if (command == null || !hc1.containsKey(command) || data is! num) {
      return _reply(request, 404, {'message': 'no $command in thermostat'});
    }
    hc1[command] = data;
    return _reply(request, 200, {'message': 'OK'});
  }
}

/// KM200 key, derived here independently of the app code:
/// MD5(gateway password without dashes + salt) || MD5(salt + private password).
Uint8List km200Key(String gatewayPassword, String privatePassword) {
  const saltHex = '867845e97c4e29dce522b9a7d3a3e07b152bffadddbed7f5ffd842e9895ad1e4';
  final salt = [
    for (var i = 0; i < saltHex.length; i += 2) int.parse(saltHex.substring(i, i + 2), radix: 16),
  ];
  final gateway = utf8.encode(gatewayPassword.replaceAll('-', ''));
  final private = utf8.encode(privatePassword);
  return Uint8List.fromList([
    ...md5.convert([...gateway, ...salt]).bytes,
    ...md5.convert([...salt, ...private]).bytes,
  ]);
}

/// Imitates a Bosch/Buderus KM200: every body is AES-256-ECB, zero padded to
/// 16 bytes and base64 encoded. Unknown services answer 404, writes are POSTs
/// answered with 204.
class MockKm200 {
  MockKm200(Uint8List key)
      : _aes = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.ecb, padding: null));

  final enc.Encrypter _aes;

  /// Service path → value (num or String).
  final Map<String, Object> services = {
    '/gateway/versionFirmware': '04.06.07',
    '/system/sensors/temperatures/outdoor_t1': 5.4,
    '/heatingCircuits/hc1/actualSupplyTemperature': 46.5,
    '/system/sensors/temperatures/return': 37.2,
    '/dhwCircuits/dhw1/actualTemp': 53.0,
    '/heatingCircuits/hc1/currentRoomSetpoint': 21.0,
    '/heatingCircuits/hc1/operationMode': 'auto',
  };

  static const writeable = {
    '/heatingCircuits/hc1/manualRoomSetpoint',
    '/heatingCircuits/hc1/temporaryRoomSetpoint',
  };

  /// Path and decrypted JSON of every accepted write.
  final List<List<Object>> writes = [];

  /// "METHOD /path" of every request.
  final List<String> requests = [];

  late final HttpServer _server;
  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> stop() => _server.close(force: true);

  String _encrypt(Map<String, dynamic> json) {
    final plain = utf8.encode(jsonEncode(json));
    final padded = Uint8List((plain.length + 15) ~/ 16 * 16)..setAll(0, plain);
    return _aes.encryptBytes(padded).base64;
  }

  Map<String, dynamic> _decrypt(String base64Body) {
    final bytes = _aes.decryptBytes(enc.Encrypted.fromBase64(base64Body.trim()));
    final end = bytes.indexOf(0);
    return jsonDecode(utf8.decode(bytes.sublist(0, end < 0 ? bytes.length : end))) as Map<String, dynamic>;
  }

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    requests.add('${request.method} $path');
    final body = await utf8.decodeStream(request);
    final response = request.response;

    if (request.method == 'GET' && services.containsKey(path)) {
      final value = services[path]!;
      response
        ..headers.contentType = ContentType.json
        ..write(_encrypt({
          'id': path,
          'type': value is String ? 'stringValue' : 'floatValue',
          'writeable': 0,
          'recordable': 0,
          'value': value,
          if (value is num) 'unitOfMeasure': 'C',
        }));
    } else if (request.method == 'GET') {
      response.statusCode = HttpStatus.notFound;
    } else if (request.method == 'POST' && writeable.contains(path)) {
      try {
        final json = _decrypt(body);
        writes.add([path, json]);
        services['/heatingCircuits/hc1/currentRoomSetpoint'] = json['value'] as num;
        response.statusCode = HttpStatus.noContent;
      } catch (_) {
        response.statusCode = HttpStatus.badRequest; // not encrypted with our key
      }
    } else if (request.method == 'POST') {
      response.statusCode = HttpStatus.forbidden;
    } else {
      response.statusCode = HttpStatus.methodNotAllowed;
    }
    await response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowLocalHttpOverrides();

  group('BoschBuderusEmsConfig & Presets Tests', () {
    test('contains expected factory presets', () {
      final presets = BoschBuderusEmsConfig.presets;
      expect(presets.length, greaterThanOrEqualTo(6));

      final ids = presets.map((p) => p.id).toSet();
      expect(ids.contains('standard'), isTrue);
      expect(ids.contains('bbqkees'), isTrue);
      expect(ids.contains('km200_mblan'), isTrue);
      expect(ids.contains('buderus_logamatic'), isTrue);
      expect(ids.contains('bosch_junkers'), isTrue);
      expect(ids.contains('custom'), isTrue);
    });

    test('km200_mblan preset defaults to km200 gateway type', () {
      final kmPreset = BoschBuderusEmsConfig.presets.firstWhere((p) => p.id == 'km200_mblan');
      expect(kmPreset.defaultGatewayType, BoschGatewayType.km200);
      expect(kmPreset.defaultPort, 80);
    });

    test('KM200 key = MD5(gateway password + salt) || MD5(salt + private password), 32 bytes', () {
      const config = BoschBuderusEmsConfig(
        gatewayType: BoschGatewayType.km200,
        gatewayPassword: 'abCD-1234-efGH-5678',
        privatePassword: 'MySecretUserPass',
      );
      final keyBytes = config.getKm200KeyBytes();
      expect(keyBytes, hasLength(32));
      expect(keyBytes, km200Key('abCD-1234-efGH-5678', 'MySecretUserPass'));

      // Dashes of the gateway password are optional; the private password is taken as is.
      expect(config.copyWith(gatewayPassword: 'abCD1234efGH5678').getKm200KeyBytes(), keyBytes);
      expect(config.copyWith(privatePassword: 'My-Secret-UserPass').getKm200KeyBytes(), isNot(keyBytes));
      expect(config.copyWith(gatewayPassword: 'abcd-1234-efgh-5678').getKm200KeyBytes(), isNot(keyBytes));
    });

    test('a ready KM200 key is 64 hex digits; one password alone gives no key', () {
      const hex = '00112233445566778899aabbccddeeff0123456789abcdef0123456789ABCDEF';
      const hexConfig = BoschBuderusEmsConfig(gatewayType: BoschGatewayType.km200, km200Key: hex);
      final hexBytes = hexConfig.getKm200KeyBytes();
      expect(hexBytes, hasLength(32));
      expect(hexBytes!.first, 0x00);
      expect(hexBytes[1], 0x11);
      expect(hexBytes.last, 0xef);

      // The 16-byte keys of <= 1.2.10 are not a KM200 key.
      expect(
        const BoschBuderusEmsConfig(km200Key: '0123456789abcdef0123456789abcdef').getKm200KeyBytes(),
        isNull,
      );
      expect(const BoschBuderusEmsConfig(gatewayPassword: 'abCD-1234-efGH-5678').getKm200KeyBytes(), isNull);
      expect(const BoschBuderusEmsConfig().getKm200KeyBytes(), isNull);
    });

    test('default config values are valid', () {
      const config = BoschBuderusEmsConfig();
      expect(config.host, '192.168.1.120');
      expect(config.port, 80);
      expect(config.circuit, 'hc1');
      expect(config.useHttps, isFalse);
      expect(config.apiToken, isEmpty);
      expect(config.presetId, 'standard');
      expect(config.baseUrl, 'http://192.168.1.120:80');
      expect(config.getUri('/api/boiler').path, '/api/boiler');
    });

    test('baseUrl formats https correctly', () {
      const config = BoschBuderusEmsConfig(
        host: 'ems-gateway.local',
        port: 443,
        useHttps: true,
      );
      expect(config.baseUrl, 'https://ems-gateway.local:443');
    });

    test('toJson and fromJson preserves all fields', () {
      const original = BoschBuderusEmsConfig(
        host: '10.0.0.99',
        port: 8080,
        apiToken: 'secret_token_123',
        circuit: 'hc2',
        useHttps: true,
        timeoutSeconds: 8,
        gatewayType: BoschGatewayType.km200,
        gatewayPassword: 'abCD-1234-efGH-5678',
        privatePassword: 'MySecretUserPass',
        presetId: 'bbqkees',
        presetName: 'BBQKees Gateway-E32 / S3',
      );

      final jsonMap = original.toJson();
      final restored = BoschBuderusEmsConfig.fromJson(
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>,
      );

      expect(restored.host, '10.0.0.99');
      expect(restored.port, 8080);
      expect(restored.apiToken, 'secret_token_123');
      expect(restored.circuit, 'hc2');
      expect(restored.useHttps, isTrue);
      expect(restored.timeoutSeconds, 8);
      expect(restored.presetId, 'bbqkees');
      expect(restored.presetName, 'BBQKees Gateway-E32 / S3');
      expect(restored.toJson(), original.toJson());
      expect(restored.getKm200KeyBytes(), original.getKm200KeyBytes());
    });

    test('copyWith properly updates specific properties', () {
      const base = BoschBuderusEmsConfig();
      final updated = base.copyWith(
        host: '192.168.178.60',
        port: 8081,
        circuit: 'hc2',
      );

      expect(updated.host, '192.168.178.60');
      expect(updated.port, 8081);
      expect(updated.circuit, 'hc2');
      expect(updated.useHttps, base.useHttps);
    });

    test('secure storage save and load cycle', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      final initial = await BoschBuderusEmsConfig.load(storage);
      expect(initial.presetId, 'standard');

      final custom = initial.copyWith(
        presetId: 'custom',
        host: '192.168.2.55',
        apiToken: 'my-bearer-token',
      );
      await custom.save(storage);

      final loaded = await BoschBuderusEmsConfig.load(storage);
      expect(loaded.presetId, 'custom');
      expect(loaded.host, '192.168.2.55');
      expect(loaded.apiToken, 'my-bearer-token');
    });
  });

  final throwsModbusError = throwsA(isA<ModbusCommunicationException>());

  group('BoschBuderusEmsController basics', () {
    test('initial state and capabilities are correct', () {
      final controller = BoschBuderusEmsController();

      expect(controller.id, 'bosch_buderus_ems');
      expect(controller.brandName, contains('Bosch'));
      expect(controller.isConnected, isFalse);
      expect(controller.protocol, ConnectionProtocol.restApi);
      expect(controller.capabilities.supportsHeatingCurveShift, isTrue);
      expect(controller.capabilities.supportsRoomTarget, isTrue);
      expect(controller.capabilities.supportsHotWater, isTrue);
      expect(controller.capabilities.supportsOutdoorTemp, isTrue);
      expect(controller.capabilities.supportsReturnTemp, isTrue);
    });

    test('disconnect when disconnected completes cleanly', () async {
      final controller = BoschBuderusEmsController();
      await expectLater(controller.disconnect(), completes);
      expect(controller.isConnected, isFalse);
    });

    test('writes without a connection throw', () async {
      final controller = BoschBuderusEmsController();
      await expectLater(controller.setRoomTarget(21.0), throwsModbusError);
      await expectLater(controller.setHeatingCurveShift(1.0), throwsModbusError);
    });
  });

  group('EMS-ESP REST API', () {
    late MockEmsEsp gateway;

    setUp(() async {
      gateway = MockEmsEsp();
      await gateway.start();
    });

    tearDown(() => gateway.stop());

    BoschBuderusEmsConfig config({String apiToken = MockEmsEsp.token}) => BoschBuderusEmsConfig(
          host: '127.0.0.1',
          port: gateway.port,
          circuit: 'hc1',
          apiToken: apiToken,
          timeoutSeconds: 2,
        );

    Future<BoschBuderusEmsController> connect({String apiToken = MockEmsEsp.token}) async {
      final controller = BoschBuderusEmsController(config: config(apiToken: apiToken));
      await controller.connect(host: '127.0.0.1', port: gateway.port);
      expect(controller.isConnected, isTrue);
      return controller;
    }

    test('EMS-ESP 3.6: reads boiler (flat wwcurtemp) and thermostat hc1', () async {
      final controller = await connect();

      final telemetry = await controller.readTelemetry();
      expect(telemetry.flowTemp, 46.5);
      expect(telemetry.returnTemp, 37.2);
      expect(telemetry.outdoorTemp, 5.4);
      expect(telemetry.hotWaterTemp, 53.0);
      expect(telemetry.roomTarget, 21.0); // seltemp, not currtemp (20.8)
      expect(telemetry.heatingCurveShift, 0.0);
      expect(telemetry.spread, closeTo(9.3, 0.01));

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });

    test('EMS-ESP 3.7: hot water comes from the nested dhw.curtemp', () async {
      gateway.boiler = {
        'curflowtemp': 46.5,
        'rettemp': 37.2,
        'outdoortemp': 5.4,
        'dhw': {'curtemp': 53.0, 'settemp': 55, 'activated': 'on'},
      };
      final controller = await connect();

      final telemetry = await controller.readTelemetry();
      expect(telemetry.hotWaterTemp, 53.0);
      expect(telemetry.flowTemp, 46.5);
      expect(telemetry.returnTemp, 37.2);
      expect(telemetry.outdoorTemp, 5.4);
      await controller.disconnect();
    });

    test('writes seltemp and offsettemp as {"cmd", "data", "id"} with the Bearer token', () async {
      final controller = await connect();

      await controller.setRoomTarget(22.5);
      await controller.setHeatingCurveShift(-2.0);

      expect(gateway.posts, [
        ['/api/thermostat', {'cmd': 'seltemp', 'data': 22.5, 'id': 1}],
        ['/api/thermostat', {'cmd': 'offsettemp', 'data': -2.0, 'id': 1}],
      ]);
      final telemetry = await controller.readTelemetry();
      expect(telemetry.roomTarget, 22.5);
      expect(telemetry.heatingCurveShift, -2.0);
      await controller.disconnect();
    });

    test('a thermostat without offsettemp: shift is empty and writing it throws', () async {
      gateway.hc1 = {'seltemp': 21, 'currtemp': 20.8};
      final controller = await connect();

      expect((await controller.readTelemetry()).heatingCurveShift, isNull);
      await expectLater(controller.setHeatingCurveShift(2.0), throwsModbusError); // 404 from the gateway
      expect(gateway.hc1.containsKey('offsettemp'), isFalse);
      expect(gateway.hc1['seltemp'], 21);
      await controller.disconnect();
    });

    for (final badToken in ['', 'wrong-token']) {
      test('POST with ${badToken.isEmpty ? 'no' : 'an invalid'} token → 401 → error mentions the token', () async {
        // Reading works without token …
        final controller = await connect(apiToken: badToken);
        expect((await controller.readTelemetry()).flowTemp, 46.5);

        // … writing does not.
        final tokenError = throwsA(isA<ModbusCommunicationException>()
            .having((e) => e.message.toLowerCase(), 'message', contains('token')));
        await expectLater(controller.setRoomTarget(22.5), tokenError);
        await expectLater(controller.setHeatingCurveShift(1.0), tokenError);
        expect(gateway.posts, isEmpty);
        expect(gateway.hc1['seltemp'], 21);
        await controller.disconnect();
      });
    }

    test('testConnection reads values without a prior connect', () async {
      final result = await BoschBuderusEmsController.testConnection(config());
      expect(result['success'], isTrue);
      expect(result['flowTemp'], 46.5);
      expect(result['returnTemp'], 37.2);
      expect(result['outdoorTemp'], 5.4);
      expect(result['hotWaterTemp'], 53.0);
      expect(result['roomTarget'], 21.0);
    });

    test('a web server that is not an EMS-ESP is rejected on connect', () async {
      gateway.boiler = {};
      gateway.hc1 = {};
      final controller = BoschBuderusEmsController(config: config());
      await expectLater(controller.connect(host: '127.0.0.1', port: gateway.port), throwsModbusError);
      expect(controller.isConnected, isFalse);
    });
  });

  group('KM200 (AES-256-ECB)', () {
    const gatewayPassword = 'abCD-1234-efGH-5678';
    const privatePassword = 'MySecretUserPass';
    late MockKm200 km200;

    setUp(() async {
      km200 = MockKm200(km200Key(gatewayPassword, privatePassword));
      await km200.start();
    });

    tearDown(() => km200.stop());

    BoschBuderusEmsConfig config({String private = privatePassword}) => BoschBuderusEmsConfig(
          gatewayType: BoschGatewayType.km200,
          host: '127.0.0.1',
          port: km200.port,
          circuit: 'hc1',
          gatewayPassword: gatewayPassword,
          privatePassword: private,
          timeoutSeconds: 2,
        );

    Future<BoschBuderusEmsController> connect() async {
      final controller = BoschBuderusEmsController(config: config());
      await controller.connect(host: '127.0.0.1', port: km200.port);
      expect(controller.isConnected, isTrue);
      return controller;
    }

    test('decrypts the services with the key derived from both passwords', () async {
      final controller = await connect();

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 5.4);
      expect(telemetry.flowTemp, 46.5);
      expect(telemetry.returnTemp, 37.2);
      expect(telemetry.hotWaterTemp, 53.0);
      expect(telemetry.roomTarget, 21.0);
      expect(telemetry.heatingCurveShift, isNull);
      expect(km200.requests, contains('GET /gateway/versionFirmware'));
      expect(km200.requests.where((r) => !r.startsWith('GET ')), isEmpty);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });

    test('works with a ready 64-digit hex key instead of the passwords', () async {
      final hex = km200Key(gatewayPassword, privatePassword)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final controller = BoschBuderusEmsController(
        config: BoschBuderusEmsConfig(
          gatewayType: BoschGatewayType.km200,
          host: '127.0.0.1',
          port: km200.port,
          km200Key: hex,
          timeoutSeconds: 2,
        ),
      );
      await controller.connect(host: '127.0.0.1', port: km200.port);
      expect((await controller.readTelemetry()).flowTemp, 46.5);
      await controller.disconnect();
    });

    test('a sensor reporting -3276.8 is not connected → null', () async {
      km200.services['/system/sensors/temperatures/return'] = -3276.8;
      km200.services['/dhwCircuits/dhw1/actualTemp'] = -3276.8;
      final controller = await connect();

      final telemetry = await controller.readTelemetry();
      expect(telemetry.returnTemp, isNull);
      expect(telemetry.hotWaterTemp, isNull);
      expect(telemetry.outdoorTemp, 5.4);
      expect(telemetry.flowTemp, 46.5);
      await controller.disconnect();
    });

    test('a missing service (404) is skipped, not an error', () async {
      km200.services.remove('/dhwCircuits/dhw1/actualTemp');
      km200.services.remove('/gateway/versionFirmware');
      final controller = await connect();
      final telemetry = await controller.readTelemetry();
      expect(telemetry.hotWaterTemp, isNull);
      expect(telemetry.flowTemp, 46.5);
      await controller.disconnect();
    });

    test('mode "auto": room setpoint is POSTed encrypted to temporaryRoomSetpoint', () async {
      final controller = await connect();

      await controller.setRoomTarget(22.5);
      expect(km200.writes, [
        ['/heatingCircuits/hc1/temporaryRoomSetpoint', {'value': 22.5}],
      ]);
      expect(km200.requests, contains('POST /heatingCircuits/hc1/temporaryRoomSetpoint'));
      expect(km200.requests.where((r) => r.startsWith('PUT ')), isEmpty);
      expect((await controller.readTelemetry()).roomTarget, 22.5);
      await controller.disconnect();
    });

    test('mode "manual": room setpoint goes to manualRoomSetpoint', () async {
      km200.services['/heatingCircuits/hc1/operationMode'] = 'manual';
      final controller = await connect();

      await controller.setRoomTarget(19.0);
      expect(km200.writes, [
        ['/heatingCircuits/hc1/manualRoomSetpoint', {'value': 19.0}],
      ]);
      await controller.disconnect();
    });

    test('no curve shift on the KM200: capability off, write throws, nothing is sent', () async {
      final controller = await connect();
      expect(controller.capabilities.supportsHeatingCurveShift, isFalse);
      expect(controller.capabilities.supportsRoomTarget, isTrue);

      km200.requests.clear();
      await expectLater(controller.setHeatingCurveShift(2.0), throwsModbusError);
      expect(km200.requests, isEmpty);
      await controller.disconnect();
    });

    test('wrong passwords: the gateway answers but nothing decrypts → clear error', () async {
      final decryptError = throwsA(isA<ModbusCommunicationException>()
          .having((e) => e.message, 'message', contains('entschlüsseln')));

      final controller = BoschBuderusEmsController(config: config(private: 'NotMyPassword'));
      await expectLater(controller.connect(host: '127.0.0.1', port: km200.port), decryptError);
      expect(controller.isConnected, isFalse);

      final probe = await BoschBuderusEmsController.testConnection(config(private: 'NotMyPassword'));
      expect(probe['success'], isFalse);
      expect(probe['message'], contains('entschlüsseln'));
    });

    test('missing passwords are reported before any request', () async {
      final controller = BoschBuderusEmsController(
        config: BoschBuderusEmsConfig(
          gatewayType: BoschGatewayType.km200,
          host: '127.0.0.1',
          port: km200.port,
          timeoutSeconds: 2,
        ),
      );
      await expectLater(controller.connect(host: '127.0.0.1', port: km200.port), throwsModbusError);
      expect(km200.requests, isEmpty);
    });

    test('testConnection reads values without a prior connect', () async {
      final result = await BoschBuderusEmsController.testConnection(config());
      expect(result['success'], isTrue);
      expect(result['outdoorTemp'], 5.4);
      expect(result['flowTemp'], 46.5);
      expect(result['roomTarget'], 21.0);
    });
  });
}
