import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';

// Config, preset and migration tests. The Modbus wire behaviour (Stiebel ISG,
// Samson TROVIS, failing devices) is tested against a Modbus TCP server in
// virtual_controllers_test.dart.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GenericModbusConfig & Presets Tests', () {
    test('contains expected factory presets', () {
      expect(
        GenericModbusConfig.presets.map((p) => p.id).toSet(),
        {'standard', 'stiebel_isg', 'custom', 'samson_trovis'},
      );
      expect(GenericModbusConfig.presets.first.id, 'standard');
    });

    test('stiebel_isg preset: input registers 506/514/515/521, comfort temperature 1501, no shift', () {
      final preset = GenericModbusConfig.presets.firstWhere((p) => p.id == 'stiebel_isg');
      // ISG register numbers are 1-based: 507/515/516/522 and 1502.
      expect(preset.outdoorRegister, 506);
      expect(preset.flowRegister, 514);
      expect(preset.returnRegister, 515);
      expect(preset.hotWaterRegister, 521);
      expect(preset.roomTargetRegister, 1501);
      expect(preset.heatingCurveShiftRegister, isNull);
      expect(preset.isHoldingRegister, isFalse);
      expect(preset.pollingIntervalSeconds, 5);
      expect(preset.multiplier, 0.1);
      expect(preset.dataType, ModbusRegisterDataType.int16);
    });

    test('samson_trovis preset is read-only on holding registers', () {
      final trovis = GenericModbusConfig.presets.firstWhere((p) => p.id == 'samson_trovis');
      // HR 40010/40013/40017/40023 → protocol address HR − 40001; read-only
      expect([trovis.outdoorRegister, trovis.flowRegister, trovis.returnRegister, trovis.hotWaterRegister], [9, 12, 16, 22]);
      expect(trovis.roomTargetRegister, isNull);
      expect(trovis.heatingCurveShiftRegister, isNull);
      expect(trovis.isHoldingRegister, isTrue);
      expect(trovis.defaultUnitId, 255);
    });

    test('default config values are valid and have no write registers', () {
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
      expect(config.roomTargetRegister, isNull);
      expect(config.heatingCurveShiftRegister, isNull);
    });

    test('toJson and fromJson preserves all fields including wordOrder and dataType', () {
      const original = GenericModbusConfig(
        presetId: 'custom',
        presetName: 'Benutzerdefiniert',
        host: '10.0.0.42',
        port: 5020,
        unitId: 2,
        outdoorRegister: 100,
        flowRegister: 101,
        returnRegister: 102,
        hotWaterRegister: 103,
        roomTargetRegister: 105,
        heatingCurveShiftRegister: 106,
        multiplier: 0.01,
        isHoldingRegister: false,
        wordOrder: ModbusWordOrder.wordSwap,
        dataType: ModbusRegisterDataType.int32,
        pollingIntervalSeconds: 8,
      );

      final restored = GenericModbusConfig.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
    });

    for (final removedId in ['luxtronik', 'ta_cmi', 'siemens_synco', 'wolf_bm2']) {
      test('stored config of removed preset "$removedId" loads as read-only custom', () {
        final restored = GenericModbusConfig.fromJson({
          'presetId': removedId,
          'presetName': 'Some invented preset',
          'host': '10.0.0.42',
          'port': 5020,
          'unitId': 2,
          'outdoorRegister': 100,
          'flowRegister': 101,
          'returnRegister': 102,
          'hotWaterRegister': 103,
          'roomTargetRegister': 105,
          'heatingCurveShiftRegister': 106,
          'multiplier': 0.1,
          'isHoldingRegister': true,
          'wordOrder': 'wordSwap',
          'dataType': 'int32',
          'pollingIntervalSeconds': 8,
        });

        expect(restored.presetId, 'custom');
        expect(restored.presetName, 'Benutzerdefiniert');
        expect(restored.roomTargetRegister, isNull);
        expect(restored.heatingCurveShiftRegister, isNull);
        // Connection and read settings are kept.
        expect(restored.host, '10.0.0.42');
        expect(restored.port, 5020);
        expect(restored.unitId, 2);
        expect(
          [restored.outdoorRegister, restored.flowRegister, restored.returnRegister, restored.hotWaterRegister],
          [100, 101, 102, 103],
        );
        expect(restored.wordOrder, ModbusWordOrder.wordSwap);
        expect(restored.dataType, ModbusRegisterDataType.int32);
      });
    }

    test('stored stiebel_isg config with the old 501 map migrates to the real map', () {
      final restored = GenericModbusConfig.fromJson({
        'presetId': 'stiebel_isg',
        'presetName': 'Stiebel Eltron / Tecalor (ISG Web)',
        'host': '10.0.0.42',
        'port': 5020,
        'unitId': 7,
        'outdoorRegister': 501,
        'flowRegister': 502,
        'returnRegister': 503,
        'hotWaterRegister': 504,
        'roomTargetRegister': 1501,
        'heatingCurveShiftRegister': 1502,
        'multiplier': 0.1,
        'isHoldingRegister': true,
        'wordOrder': 'bigEndian',
        'dataType': 'int16',
        'pollingIntervalSeconds': 5,
      });

      final preset = GenericModbusConfig.presets.firstWhere((p) => p.id == 'stiebel_isg');
      final expected = GenericModbusConfig.fromPreset(preset, host: '10.0.0.42').copyWith(port: 5020, unitId: 7);
      expect(restored.toJson(), expected.toJson());
      expect(restored.outdoorRegister, 506);
      expect(restored.isHoldingRegister, isFalse);
      expect(restored.heatingCurveShiftRegister, isNull);
    });

    test('a stiebel_isg config already on the new map is loaded unchanged', () {
      final preset = GenericModbusConfig.presets.firstWhere((p) => p.id == 'stiebel_isg');
      final current = GenericModbusConfig.fromPreset(preset).copyWith(hotWaterRegister: 600);
      expect(GenericModbusConfig.fromJson(current.toJson()).toJson(), current.toJson());
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
      // The default config has no write registers.
      expect(controller.capabilities.supportsHeatingCurveShift, isFalse);
      expect(controller.capabilities.supportsRoomTarget, isFalse);
    });

    test('capabilities follow the configured write registers', () {
      final preset = GenericModbusConfig.presets.firstWhere((p) => p.id == 'stiebel_isg');
      final controller = GenericModbusController(config: GenericModbusConfig.fromPreset(preset));
      expect(controller.capabilities.supportsRoomTarget, isTrue);
      expect(controller.capabilities.supportsHeatingCurveShift, isFalse);
    });

    test('writes without a configured register throw instead of writing somewhere', () async {
      final controller = GenericModbusController();
      final throwsModbusError = throwsA(isA<ModbusCommunicationException>());
      await expectLater(controller.setRoomTarget(21.0), throwsModbusError);
      await expectLater(controller.setHeatingCurveShift(1.0), throwsModbusError);
    });

    test('readTelemetry without a connection throws', () async {
      await expectLater(
        GenericModbusController().readTelemetry(),
        throwsA(isA<ModbusCommunicationException>()),
      );
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
