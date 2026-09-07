import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/controllers/bosch_buderus_ems_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

class _AllowLocalHttpOverrides extends HttpOverrides {}

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

    test('KM200 AES key derivation calculates 16-byte key correctly', () {
      const config = BoschBuderusEmsConfig(
        gatewayType: BoschGatewayType.km200,
        gatewayPassword: '1234-5678-9012-3456',
        privatePassword: 'MySecretUserPass',
      );
      final keyBytes = config.getKm200KeyBytes();
      expect(keyBytes, isNotNull);
      expect(keyBytes!.length, 16);

      // Direct hex key fallback
      const hexConfig = BoschBuderusEmsConfig(
        gatewayType: BoschGatewayType.km200,
        km200Key: '0123456789abcdef0123456789abcdef',
      );
      final hexBytes = hexConfig.getKm200KeyBytes();
      expect(hexBytes, isNotNull);
      expect(hexBytes!.length, 16);
      expect(hexBytes[0], 0x01);
      expect(hexBytes[15], 0xef);
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

  group('BoschBuderusEmsController Unit & Local Mock HTTP Tests', () {
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

    test('connects to mock EMS-ESP gateway, parses telemetry, and writes setpoints', () async {
      // Spin up local test HTTP server
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      double currentTarget = 21.0;
      double currentShift = 0.0;

      final sub = server.listen((HttpRequest request) async {
        final path = request.uri.path;
        final method = request.method;

        if (method == 'GET' && path == '/api/system') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'version': '3.6.2',
              'uptime': '14d 6h',
              'status': 'connected',
            }));
          await request.response.close();
        } else if (method == 'GET' && path == '/api/boiler') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'curflowtemp': 46.5,
              'rettemp': 37.2,
              'outdoortemp': 5.4,
              'wwcurtemp': 53.0,
            }));
          await request.response.close();
        } else if (method == 'GET' && path == '/api/thermostat') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'hc1': {
                'seltemp': currentTarget,
                'offset': currentShift,
                'currtemp': 20.8,
              }
            }));
          await request.response.close();
        } else if (method == 'POST' && path.startsWith('/api/thermostat')) {
          final body = await utf8.decodeStream(request);
          final map = jsonDecode(body) as Map<String, dynamic>;
          if (map['cmd'] == 'seltemp' || map.containsKey('value')) {
            currentTarget = ((map['data'] ?? map['value']) as num).toDouble();
          }
          if (map['cmd'] == 'offset' || path.endsWith('/offset')) {
            currentShift = ((map['data'] ?? map['value']) as num).toDouble();
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

        // 1. Diagnostic testConnection verification
        final testRes = await BoschBuderusEmsController.testConnection(config);
        expect(testRes['success'], isTrue);
        expect(testRes['version'], '3.6.2');
        expect(testRes['flowTemp'], 46.5);
        expect(testRes['returnTemp'], 37.2);
        expect(testRes['outdoorTemp'], 5.4);
        expect(testRes['hotWaterTemp'], 53.0);
        expect(testRes['roomTarget'], 21.0);

        // 2. Real controller connect lifecycle
        final controller = BoschBuderusEmsController(config: config);
        await controller.connect(host: '127.0.0.1', port: port);
        expect(controller.isConnected, isTrue);

        // 3. Read telemetry
        final telemetry = await controller.readTelemetry();
        expect(telemetry.flowTemp, 46.5);
        expect(telemetry.returnTemp, 37.2);
        expect(telemetry.outdoorTemp, 5.4);
        expect(telemetry.hotWaterTemp, 53.0);
        expect(telemetry.roomTarget, 21.0);
        expect(telemetry.spread, closeTo(9.3, 0.01));

        // 4. Set Room Target
        await controller.setRoomTarget(22.5);
        expect(currentTarget, 22.5);

        // 5. Set Heating Curve Shift
        await controller.setHeatingCurveShift(2.0);
        expect(currentShift, 2.0);

        // 6. Clean disconnect
        await controller.disconnect();
        expect(controller.isConnected, isFalse);
      } finally {
        await sub.cancel();
        await server.close(force: true);
      }
    });
  });
}
