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
      expect(presets.length, greaterThanOrEqualTo(7));

      final ids = presets.map((p) => p.id).toSet();
      expect(ids.contains('standard'), isTrue);
      expect(ids.contains('stiebel_isg'), isTrue);
      expect(ids.contains('luxtronik'), isTrue);
      expect(ids.contains('ta_cmi'), isTrue);
      expect(ids.contains('siemens_synco'), isTrue);
      expect(ids.contains('wolf_bm2'), isTrue);
      expect(ids.contains('custom'), isTrue);
    });

    test('stiebel_isg preset has ISG registers and 5s polling throttle', () {
      final preset = GenericModbusConfig.presets.firstWhere((p) => p.id == 'stiebel_isg');
      expect(preset.outdoorRegister, 501);
      expect(preset.flowRegister, 502);
      expect(preset.returnRegister, 503);
      expect(preset.hotWaterRegister, 504);
      expect(preset.roomTargetRegister, 1501);
      expect(preset.heatingCurveShiftRegister, 1502);
      expect(preset.pollingIntervalSeconds, 5);
      expect(preset.multiplier, 0.1);
    });

    test('luxtronik preset has 32-bit register and word-swap (CDAB)', () {
      final preset = GenericModbusConfig.presets.firstWhere((p) => p.id == 'luxtronik');
      expect(preset.wordOrder, ModbusWordOrder.wordSwap);
      expect(preset.dataType, ModbusRegisterDataType.int32);
      expect(preset.outdoorRegister, 100);
      expect(preset.flowRegister, 101);
      expect(preset.returnRegister, 102);
    });

    test('default config values are valid', () {
      const config = GenericModbusConfig();
      expect(config.presetId, 'standard');
      expect(config.host, '192.168.1.50');
      expect(config.port, 502);
      expect(config.unitId, 1);
      expect(config.multiplier, 0.1);
      expect(config.isHoldingRegister, isTrue);
      expect(config.wordOrder, ModbusWordOrder.bigEndian);
      expect(config.dataType, ModbusRegisterDataType.int16);
      expect(config.pollingIntervalSeconds, 10);
      expect(config.outdoorRegister, 1);
      expect(config.flowRegister, 2);
      expect(config.returnRegister, 3);
      expect(config.hotWaterRegister, 4);
      expect(config.roomTargetRegister, 5);
      expect(config.heatingCurveShiftRegister, 6);
    });

    test('toJson and fromJson preserves all fields including wordOrder and dataType', () {
      const original = GenericModbusConfig(
        presetId: 'luxtronik',
        presetName: 'Luxtronik 2.0 / 2.1 (Alpha Innotec / Novelan)',
        host: '10.0.0.42',
        port: 5020,
        unitId: 2,
        outdoorRegister: 100,
        flowRegister: 101,
        returnRegister: 102,
        hotWaterRegister: 103,
        roomTargetRegister: 105,
        heatingCurveShiftRegister: 106,
        multiplier: 0.1,
        isHoldingRegister: true,
        wordOrder: ModbusWordOrder.wordSwap,
        dataType: ModbusRegisterDataType.int32,
        pollingIntervalSeconds: 8,
      );

      final jsonMap = original.toJson();
      final restored = GenericModbusConfig.fromJson(
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>,
      );

      expect(restored.presetId, 'luxtronik');
      expect(restored.presetName, 'Luxtronik 2.0 / 2.1 (Alpha Innotec / Novelan)');
      expect(restored.host, '10.0.0.42');
      expect(restored.port, 5020);
      expect(restored.unitId, 2);
      expect(restored.outdoorRegister, 100);
      expect(restored.flowRegister, 101);
      expect(restored.returnRegister, 102);
      expect(restored.hotWaterRegister, 103);
      expect(restored.roomTargetRegister, 105);
      expect(restored.heatingCurveShiftRegister, 106);
      expect(restored.multiplier, 0.1);
      expect(restored.isHoldingRegister, isTrue);
      expect(restored.wordOrder, ModbusWordOrder.wordSwap);
      expect(restored.dataType, ModbusRegisterDataType.int32);
      expect(restored.pollingIntervalSeconds, 8);
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
