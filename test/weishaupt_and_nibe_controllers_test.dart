import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';
import 'package:heizungstrainer/controllers/weishaupt_wem_controller.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';
import 'package:heizungstrainer/controllers/nibe_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WeishauptWemConfig & Controller Tests', () {
    test('contains expected factory presets', () {
      final presets = WeishauptWemConfig.presets;
      expect(presets.length, greaterThanOrEqualTo(4));

      final ids = presets.map((p) => p.id).toSet();
      expect(ids.contains('wem_wwp_split'), isTrue);
      expect(ids.contains('wem_wtc_gw'), isTrue);
      expect(ids.contains('wem_biblock'), isTrue);
      expect(ids.contains('custom'), isTrue);
    });

    test('default config values are valid', () {
      const config = WeishauptWemConfig();
      expect(config.host, '192.168.1.150');
      expect(config.port, 502);
      expect(config.unitId, 1);
      expect(config.multiplier, 0.1);
      expect(config.outdoorRegister, 3101);
      expect(config.flowRegister, 3102);
      expect(config.returnRegister, 3103);
      expect(config.hotWaterRegister, 3104);
      expect(config.roomTargetRegister, 3105);
      expect(config.heatingCurveShiftRegister, 3106);
      expect(config.isHoldingRegister, isTrue);
    });

    test('toJson and fromJson preserves all fields', () {
      const original = WeishauptWemConfig(
        presetId: 'wem_wtc_gw',
        presetName: 'Weishaupt WTC-GW (Gas-Brennwert WEM)',
        host: '10.0.0.88',
        port: 502,
        unitId: 2,
        outdoorRegister: 1,
        flowRegister: 2,
        returnRegister: 3,
        hotWaterRegister: 4,
        roomTargetRegister: 5,
        heatingCurveShiftRegister: 6,
        multiplier: 0.1,
        isHoldingRegister: true,
      );

      final jsonMap = original.toJson();
      final restored = WeishauptWemConfig.fromJson(
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>,
      );

      expect(restored.presetId, 'wem_wtc_gw');
      expect(restored.host, '10.0.0.88');
      expect(restored.unitId, 2);
      expect(restored.outdoorRegister, 1);
      expect(restored.flowRegister, 2);
    });

    test('secure storage save and load cycle', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      final initial = await WeishauptWemConfig.load(storage);
      expect(initial.presetId, 'wem_wwp_split');

      final custom = initial.copyWith(
        presetId: 'custom',
        host: '192.168.178.150',
      );
      await custom.save(storage);

      final loaded = await WeishauptWemConfig.load(storage);
      expect(loaded.presetId, 'custom');
      expect(loaded.host, '192.168.178.150');
    });

    test('controller metadata and capabilities are correct', () {
      final controller = WeishauptWemController();
      expect(controller.id, 'weishaupt_wem');
      expect(controller.brandName, 'Weishaupt');
      expect(controller.protocol, ConnectionProtocol.modbusTcp);
      expect(controller.capabilities.supportsHeatingCurveShift, isTrue);
      expect(controller.capabilities.supportsRoomTarget, isTrue);
      expect(controller.capabilities.supportsHotWater, isTrue);
      expect(controller.capabilities.supportsReturnTemp, isTrue);
      expect(controller.capabilities.supportsOutdoorTemp, isTrue);
    });
  });

  group('NibeModbusConfig & Controller Tests', () {
    test('contains expected factory presets', () {
      final presets = NibeModbusConfig.presets;
      expect(presets.length, greaterThanOrEqualTo(4));

      final ids = presets.map((p) => p.id).toSet();
      expect(ids.contains('nibe_s_series'), isTrue);
      expect(ids.contains('nibe_f_series_modbus40'), isTrue);
      expect(ids.contains('nibe_smo40'), isTrue);
      expect(ids.contains('custom'), isTrue);
    });

    test('default config values are valid for S-Series', () {
      const config = NibeModbusConfig();
      expect(config.host, '192.168.1.160');
      expect(config.port, 502);
      expect(config.unitId, 1);
      expect(config.multiplier, 0.1);
      expect(config.outdoorRegister, 1);
      expect(config.flowRegister, 5);
      expect(config.returnRegister, 7);
      expect(config.hotWaterRegister, 8);
      expect(config.roomTargetRegister, 26);
      expect(config.heatingCurveShiftRegister, 30);
      expect(config.isHoldingRegister, isTrue);
    });

    test('preset for F-Series with Modbus 40 maps correct registers', () {
      final preset = NibeModbusConfig.presets.firstWhere((p) => p.id == 'nibe_f_series_modbus40');
      final config = NibeModbusConfig.fromPreset(preset);

      expect(config.outdoorRegister, 40004);
      expect(config.flowRegister, 40008);
      expect(config.returnRegister, 40012);
      expect(config.hotWaterRegister, 40013);
      // 47011 = Heat Offset S1; 47007 (curve slope) must not be used as shift.
      expect(config.roomTargetRegister, isNull);
      expect(config.heatingCurveShiftRegister, 47011);
    });

    test('legacy F-Series config (shift=47007) is repaired on load', () {
      final legacy = NibeModbusConfig.fromJson({
        'presetId': 'nibe_f_series_modbus40',
        'roomTargetRegister': 47011,
        'heatingCurveShiftRegister': 47007,
      });
      expect(legacy.heatingCurveShiftRegister, 47011);
      expect(legacy.roomTargetRegister, isNull);
    });

    test('explicitly disabled room register stays disabled after reload', () {
      const cfg = NibeModbusConfig(roomTargetRegister: null);
      final restored = NibeModbusConfig.fromJson(cfg.toJson());
      expect(restored.roomTargetRegister, isNull);
    });

    test('toJson and fromJson preserves all fields', () {
      const original = NibeModbusConfig(
        presetId: 'nibe_f_series_modbus40',
        presetName: 'NIBE F-Serie (F1155 / F1255 mit Modbus 40)',
        host: '10.0.0.77',
        port: 502,
        unitId: 1,
        outdoorRegister: 40004,
        flowRegister: 40008,
        returnRegister: 40012,
        hotWaterRegister: 40013,
        roomTargetRegister: 47011,
        heatingCurveShiftRegister: 47007,
        multiplier: 0.1,
        isHoldingRegister: true,
      );

      final jsonMap = original.toJson();
      final restored = NibeModbusConfig.fromJson(
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>,
      );

      expect(restored.presetId, 'nibe_f_series_modbus40');
      expect(restored.host, '10.0.0.77');
      expect(restored.outdoorRegister, 40004);
      expect(restored.flowRegister, 40008);
    });

    test('secure storage save and load cycle', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      final initial = await NibeModbusConfig.load(storage);
      expect(initial.presetId, 'nibe_s_series');

      final custom = initial.copyWith(
        presetId: 'custom',
        host: '192.168.178.160',
      );
      await custom.save(storage);

      final loaded = await NibeModbusConfig.load(storage);
      expect(loaded.presetId, 'custom');
      expect(loaded.host, '192.168.178.160');
    });

    test('controller metadata and capabilities are correct', () {
      final controller = NibeModbusController();
      expect(controller.id, 'nibe_modbus');
      expect(controller.brandName, 'NIBE');
      expect(controller.protocol, ConnectionProtocol.modbusTcp);
      expect(controller.capabilities.supportsHeatingCurveShift, isTrue);
      expect(controller.capabilities.supportsRoomTarget, isTrue);
      expect(controller.capabilities.supportsHotWater, isTrue);
      expect(controller.capabilities.supportsReturnTemp, isTrue);
      expect(controller.capabilities.supportsOutdoorTemp, isTrue);
    });
  });
}
