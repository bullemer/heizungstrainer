import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GenericModbusConfig & Presets Tests', () {
    test('contains expected factory presets', () {
      final presets = GenericModbusConfig.presets;
      expect(presets.length, greaterThanOrEqualTo(5));

      final ids = presets.map((p) => p.id).toSet();
      expect(ids.contains('standard'), isTrue);
      expect(ids.contains('ta_cmi'), isTrue);
      expect(ids.contains('siemens_synco'), isTrue);
      expect(ids.contains('wolf_bm2'), isTrue);
      expect(ids.contains('custom'), isTrue);
    });

    test('default config values are valid', () {
      const config = GenericModbusConfig();
      expect(config.presetId, 'standard');
      expect(config.host, '192.168.1.50');
      expect(config.port, 502);
      expect(config.unitId, 1);
      expect(config.multiplier, 0.1);
      expect(config.isHoldingRegister, isTrue);
      expect(config.outdoorRegister, 1);
      expect(config.flowRegister, 2);
      expect(config.returnRegister, 3);
      expect(config.hotWaterRegister, 4);
      expect(config.roomTargetRegister, 5);
      expect(config.heatingCurveShiftRegister, 6);
    });

    test('toJson and fromJson preserves all fields', () {
      const original = GenericModbusConfig(
        presetId: 'ta_cmi',
        presetName: 'Technische Alternative (UVR16x2 / C.M.I.)',
        host: '10.0.0.42',
        port: 5020,
        unitId: 2,
        outdoorRegister: 1,
        flowRegister: 2,
        returnRegister: 3,
        hotWaterRegister: 4,
        roomTargetRegister: 10,
        heatingCurveShiftRegister: 11,
        multiplier: 0.01,
        isHoldingRegister: false,
      );

      final jsonMap = original.toJson();
      final restored = GenericModbusConfig.fromJson(
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>,
      );

      expect(restored.presetId, 'ta_cmi');
      expect(restored.presetName, 'Technische Alternative (UVR16x2 / C.M.I.)');
      expect(restored.host, '10.0.0.42');
      expect(restored.port, 5020);
      expect(restored.unitId, 2);
      expect(restored.outdoorRegister, 1);
      expect(restored.flowRegister, 2);
      expect(restored.returnRegister, 3);
      expect(restored.hotWaterRegister, 4);
      expect(restored.roomTargetRegister, 10);
      expect(restored.heatingCurveShiftRegister, 11);
      expect(restored.multiplier, 0.01);
      expect(restored.isHoldingRegister, isFalse);
    });

    test('copyWith properly updates specific properties', () {
      const base = GenericModbusConfig();
      final updated = base.copyWith(
        host: '192.168.178.50',
        port: 1502,
        multiplier: 1.0,
      );

      expect(updated.host, '192.168.178.50');
      expect(updated.port, 1502);
      expect(updated.multiplier, 1.0);
      expect(updated.unitId, base.unitId);
      expect(updated.flowRegister, base.flowRegister);
    });

    test('secure storage save and load cycle', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      // Should return default when empty
      final initial = await GenericModbusConfig.load(storage);
      expect(initial.presetId, 'standard');

      final custom = initial.copyWith(
        presetId: 'custom',
        host: '192.168.0.88',
        flowRegister: 300,
      );
      await custom.save(storage);

      final loaded = await GenericModbusConfig.load(storage);
      expect(loaded.presetId, 'custom');
      expect(loaded.host, '192.168.0.88');
      expect(loaded.flowRegister, 300);
    });
  });

  group('GenericModbusController Lifecycle & Telemetry Tests', () {
    test('initial state is disconnected and properties report correctly', () {
      final controller = GenericModbusController(
        config: const GenericModbusConfig(host: '127.0.0.1'),
      );

      expect(controller.id, 'generic_modbus');
      expect(controller.brandName, contains('Modbus'));
      expect(controller.isConnected, isFalse);
      expect(controller.protocol, ConnectionProtocol.modbusTcp);
      expect(controller.capabilities.supportsHeatingCurveShift, isTrue);
      expect(controller.capabilities.supportsRoomTarget, isTrue);
    });

    test('disconnect when already disconnected completes cleanly', () async {
      final controller = GenericModbusController();
      await expectLater(controller.disconnect(), completes);
      expect(controller.isConnected, isFalse);
    });

    test('ControllerTelemetry constructor maps values appropriately', () {
      final now = DateTime.now();
      final telemetry = ControllerTelemetry(
        outdoorTemp: 4.5,
        flowTemp: 48.2,
        returnTemp: 39.1,
        hotWaterTemp: 55.0,
        roomTarget: 21.0,
        heatingCurveShift: 1.5,
        timestamp: now,
      );

      expect(telemetry.outdoorTemp, 4.5);
      expect(telemetry.flowTemp, 48.2);
      expect(telemetry.returnTemp, 39.1);
      expect(telemetry.hotWaterTemp, 55.0);
      expect(telemetry.roomTarget, 21.0);
      expect(telemetry.heatingCurveShift, 1.5);
      expect(telemetry.spread, closeTo(9.1, 0.001));
      expect(telemetry.timestamp, now);
    });
  });
}
