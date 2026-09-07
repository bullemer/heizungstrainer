import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';
import 'package:heizungstrainer/controllers/vaillant_ebusd_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

class _AllowLocalHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowLocalHttpOverrides();

  group('VaillantEbusdConfig & Presets Tests', () {
    test('contains expected factory presets', () {
      final presets = VaillantEbusdConfig.presets;
      expect(presets.length, greaterThanOrEqualTo(5));

      final ids = presets.map((p) => p.id).toSet();
      expect(ids.contains('ebusd_http_json'), isTrue);
      expect(ids.contains('ebusd_sensocomfort'), isTrue);
      expect(ids.contains('ebusd_multimatic'), isTrue);
      expect(ids.contains('ebusd_calormatic'), isTrue);
      expect(ids.contains('custom'), isTrue);
    });

    test('default config values are valid', () {
      const config = VaillantEbusdConfig();
      expect(config.host, '192.168.1.140');
      expect(config.port, 8889);
      expect(config.circuit, 'bai');
      expect(config.useHttps, isFalse);
      expect(config.apiToken, isEmpty);
      expect(config.presetId, 'ebusd_http_json');
      expect(config.baseUrl, 'http://192.168.1.140:8889');
      expect(config.getUri('/data').path, '/data');
    });

    test('toJson and fromJson preserves all fields', () {
      const original = VaillantEbusdConfig(
        host: '10.0.0.145',
        port: 8889,
        circuit: '700',
        apiToken: 'ebusd_token_xyz',
        useHttps: true,
        timeoutSeconds: 8,
        presetId: 'ebusd_multimatic',
        presetName: 'Vaillant multiMATIC (VRC 700)',
      );

      final jsonMap = original.toJson();
      final restored = VaillantEbusdConfig.fromJson(
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>,
      );

      expect(restored.host, '10.0.0.145');
      expect(restored.port, 8889);
      expect(restored.circuit, '700');
      expect(restored.apiToken, 'ebusd_token_xyz');
      expect(restored.useHttps, isTrue);
      expect(restored.timeoutSeconds, 8);
      expect(restored.presetId, 'ebusd_multimatic');
      expect(restored.presetName, 'Vaillant multiMATIC (VRC 700)');
    });

    test('secure storage save and load cycle', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      final initial = await VaillantEbusdConfig.load(storage);
      expect(initial.presetId, 'ebusd_http_json');

      final custom = initial.copyWith(
        presetId: 'custom',
        host: '192.168.178.99',
        circuit: '720',
      );
      await custom.save(storage);

      final loaded = await VaillantEbusdConfig.load(storage);
      expect(loaded.presetId, 'custom');
      expect(loaded.host, '192.168.178.99');
      expect(loaded.circuit, '720');
    });
  });

  group('VaillantEbusdController Unit & Local Mock HTTP Tests', () {
    test('initial state and capabilities are correct', () {
      final controller = VaillantEbusdController();

      expect(controller.id, 'vaillant_ebusd');
      expect(controller.brandName, 'Vaillant');
      expect(controller.modelName, contains('eBUS'));
      expect(controller.isConnected, isFalse);
      expect(controller.protocol, ConnectionProtocol.restApi);
      expect(controller.capabilities.supportsHeatingCurveShift, isTrue);
      expect(controller.capabilities.supportsRoomTarget, isTrue);
      expect(controller.capabilities.supportsHotWater, isTrue);
      expect(controller.capabilities.supportsReturnTemp, isTrue);
      expect(controller.capabilities.supportsOutdoorTemp, isTrue);
    });

    test('connects to mock eBUSd gateway, parses telemetry and writes setpoints', () async {
      double simulatedRoomTarget = 20.5;
      double simulatedCurveShift = 0.0;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        final path = request.uri.path;

        if (path == '/data' || path == '/data/bai' || path == '/data/700') {
          if (request.uri.queryParameters.containsKey('value')) {
            final valStr = request.uri.queryParameters['value']!;
            final val = double.tryParse(valStr);
            if (path.contains('Hc1DesiredRoomTemp') || path.contains('DesiredRoomTemp')) {
              if (val != null) simulatedRoomTarget = val;
            }
            if (path.contains('Hc1ParallelShift') || path.contains('ParallelShift')) {
              if (val != null) simulatedCurveShift = val;
            }
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'result': 'ok', 'value': val}))
              ..close();
            return;
          }

          final mockTree = {
            'bai': {
              'messages': {
                'FlowTemp': {'value': 48.5},
                'ReturnTemp': {'value': 37.2},
                'OutdoorstempSensor': {'value': 6.8},
                'StorageTemp': {'value': 53.0},
              }
            },
            '700': {
              'messages': {
                'Hc1DesiredRoomTemp': {'value': simulatedRoomTarget},
                'Hc1ParallelShift': {'value': simulatedCurveShift},
              }
            }
          };

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(mockTree))
            ..close();
          return;
        }

        if (path.contains('Hc1DesiredRoomTemp') || path.contains('DesiredRoomTemp')) {
          final valStr = request.uri.queryParameters['value'];
          if (valStr != null) {
            simulatedRoomTarget = double.tryParse(valStr) ?? simulatedRoomTarget;
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'result': 'ok'}))
            ..close();
          return;
        }

        if (path.contains('Hc1ParallelShift') || path.contains('ParallelShift')) {
          final valStr = request.uri.queryParameters['value'];
          if (valStr != null) {
            simulatedCurveShift = double.tryParse(valStr) ?? simulatedCurveShift;
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'result': 'ok'}))
            ..close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      });

      try {
        final config = VaillantEbusdConfig(
          host: '127.0.0.1',
          port: server.port,
          circuit: '700',
        );
        final controller = VaillantEbusdController(config: config);

        // 1. Connect
        await controller.connect(host: '127.0.0.1', port: server.port);
        expect(controller.isConnected, isTrue);

        // 2. Read Telemetry
        final telemetry = await controller.readTelemetry();
        expect(telemetry.flowTemp, 48.5);
        expect(telemetry.returnTemp, 37.2);
        expect(telemetry.outdoorTemp, 6.8);
        expect(telemetry.hotWaterTemp, 53.0);
        expect(telemetry.roomTarget, 20.5);
        expect(telemetry.heatingCurveShift, 0.0);
        expect(telemetry.spread, closeTo(11.3, 0.01));

        // 3. Write setpoints
        await controller.setRoomTarget(22.0);
        expect(simulatedRoomTarget, 22.0);

        await controller.setHeatingCurveShift(2.5);
        expect(simulatedCurveShift, 2.5);

        // 4. Test connection static probe
        final probeResult = await VaillantEbusdController.testConnection(config);
        expect(probeResult['success'], isTrue);
        expect(probeResult['flowTemp'], 48.5);

        // 5. Disconnect
        await controller.disconnect();
        expect(controller.isConnected, isFalse);
      } finally {
        await server.close(force: true);
      }
    });
  });
}
