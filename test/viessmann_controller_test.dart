import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';
import 'package:heizungstrainer/controllers/viessmann_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViessmannConfig & Presets Tests', () {
    test('contains expected factory presets', () {
      final presets = ViessmannConfig.presets;
      expect(presets.length, greaterThanOrEqualTo(5));

      final ids = presets.map((p) => p.id).toSet();
      expect(ids.contains('optolink_vcontrold'), isTrue);
      expect(ids.contains('esp_optolink'), isTrue);
      expect(ids.contains('vicare_cloud'), isTrue);
      expect(ids.contains('vitotronic_200'), isTrue);
      expect(ids.contains('custom'), isTrue);
    });

    test('default config values are valid', () {
      const config = ViessmannConfig();
      expect(config.host, '192.168.1.130');
      expect(config.port, 3002);
      expect(config.circuit, '0');
      expect(config.connectionType, ViessmannConnectionType.optolinkTcp);
      expect(config.apiToken, isEmpty);
      expect(config.presetId, 'optolink_vcontrold');
    });

    test('toJson and fromJson preserves all fields', () {
      const original = ViessmannConfig(
        connectionType: ViessmannConnectionType.vicareRest,
        host: 'api.viessmann.com',
        port: 443,
        apiToken: 'secret_vicare_token',
        installationId: 'install_9876',
        circuit: '1',
        timeoutSeconds: 7,
        presetId: 'vicare_cloud',
        presetName: 'Viessmann ViCare Developer API (Cloud REST)',
      );

      final jsonMap = original.toJson();
      final restored = ViessmannConfig.fromJson(
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>,
      );

      expect(restored.connectionType, ViessmannConnectionType.vicareRest);
      expect(restored.host, 'api.viessmann.com');
      expect(restored.port, 443);
      expect(restored.apiToken, 'secret_vicare_token');
      expect(restored.installationId, 'install_9876');
      expect(restored.circuit, '1');
      expect(restored.timeoutSeconds, 7);
      expect(restored.presetId, 'vicare_cloud');
    });

    test('copyWith properly updates specific properties', () {
      const base = ViessmannConfig();
      final updated = base.copyWith(
        host: '192.168.178.70',
        port: 7362,
        circuit: '1',
      );

      expect(updated.host, '192.168.178.70');
      expect(updated.port, 7362);
      expect(updated.circuit, '1');
      expect(updated.connectionType, base.connectionType);
    });

    test('secure storage save and load cycle', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      final initial = await ViessmannConfig.load(storage);
      expect(initial.presetId, 'optolink_vcontrold');

      final custom = initial.copyWith(
        presetId: 'custom',
        host: '192.168.1.99',
        port: 7362,
      );
      await custom.save(storage);

      final loaded = await ViessmannConfig.load(storage);
      expect(loaded.presetId, 'custom');
      expect(loaded.host, '192.168.1.99');
      expect(loaded.port, 7362);
    });
  });

  group('ViessmannController Unit & Local vcontrold Mock Tests', () {
    test('initial state and capabilities are correct', () {
      final controller = ViessmannController();

      expect(controller.id, 'viessmann_vicare');
      expect(controller.brandName, contains('Viessmann'));
      expect(controller.isConnected, isFalse);
      expect(controller.protocol, ConnectionProtocol.proprietary);
      expect(controller.capabilities.supportsHeatingCurveShift, isTrue);
      expect(controller.capabilities.supportsRoomTarget, isTrue);
      expect(controller.capabilities.supportsHotWater, isTrue);
      expect(controller.capabilities.supportsOutdoorTemp, isTrue);
      expect(controller.capabilities.supportsReturnTemp, isTrue);
    });

    test('disconnect when disconnected completes cleanly', () async {
      final controller = ViessmannController();
      await expectLater(controller.disconnect(), completes);
      expect(controller.isConnected, isFalse);
    });

    test('connects to mock vcontrold TCP server, parses telemetry, and writes setpoints', () async {
      // Spin up local TCP socket server simulating vcontrold daemon
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      double currentTarget = 20.0;
      double currentNiveau = 1.0;

      final serverSub = server.listen((Socket client) {
        client.listen((data) {
          final cmd = utf8.decode(data).trim();
          if (cmd == 'getTempA') {
            client.write('4.8 Grad C\nvctrld>');
          } else if (cmd == 'getTempVl') {
            client.write('47.5 Grad C\nvctrld>');
          } else if (cmd == 'getTempRl') {
            client.write('39.0 Grad C\nvctrld>');
          } else if (cmd == 'getTempWWist') {
            client.write('54.2 Grad C\nvctrld>');
          } else if (cmd == 'getTempRaumSoll') {
            client.write('$currentTarget Grad C\nvctrld>');
          } else if (cmd == 'getNiveau') {
            client.write('$currentNiveau K\nvctrld>');
          } else if (cmd.startsWith('setTempRaumSoll')) {
            final parts = cmd.split(' ');
            if (parts.length >= 2) {
              currentTarget = double.tryParse(parts[1]) ?? currentTarget;
            }
            client.write('OK\nvctrld>');
          } else if (cmd.startsWith('setNiveau')) {
            final parts = cmd.split(' ');
            if (parts.length >= 2) {
              currentNiveau = double.tryParse(parts[1]) ?? currentNiveau;
            }
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

        // 1. Diagnostic testConnection verification
        final testRes = await ViessmannController.testConnection(config);
        expect(testRes['success'], isTrue);
        expect(testRes['outdoorTemp'], 4.8);
        expect(testRes['flowTemp'], 47.5);
        expect(testRes['returnTemp'], 39.0);
        expect(testRes['hotWaterTemp'], 54.2);
        expect(testRes['roomTarget'], 20.0);

        // 2. Real controller connect lifecycle
        final controller = ViessmannController(config: config);
        await controller.connect(host: '127.0.0.1', port: port);
        expect(controller.isConnected, isTrue);

        // 3. Read telemetry
        final telemetry = await controller.readTelemetry();
        expect(telemetry.outdoorTemp, 4.8);
        expect(telemetry.flowTemp, 47.5);
        expect(telemetry.returnTemp, 39.0);
        expect(telemetry.hotWaterTemp, 54.2);
        expect(telemetry.roomTarget, 20.0);
        expect(telemetry.heatingCurveShift, 1.0);
        expect(telemetry.spread, closeTo(8.5, 0.01));

        // 4. Set Room Target
        await controller.setRoomTarget(21.5);
        expect(currentTarget, 21.5);

        // 5. Set Heating Curve Shift (Niveau)
        await controller.setHeatingCurveShift(3.0);
        expect(currentNiveau, 3.0);

        // 6. Clean disconnect
        await controller.disconnect();
        expect(controller.isConnected, isFalse);
      } finally {
        await serverSub.cancel();
        await server.close();
      }
    });
  });
}
