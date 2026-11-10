import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';
import 'package:heizungstrainer/controllers/weishaupt_wem_controller.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';
import 'package:heizungstrainer/controllers/nibe_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

// Config, preset and migration tests. The Modbus wire behaviour of both
// drivers is tested against a Modbus TCP server in virtual_controllers_test.dart.

Map<String, dynamic> _stored(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final throwsModbusError = throwsA(isA<ModbusCommunicationException>());

  group('WeishauptWemConfig & Controller Tests', () {
    test('only the heat pump preset and "custom" are left', () {
      expect(WeishauptWemConfig.presets.map((p) => p.id), ['wem_wwp_split', 'custom']);
    });

    test('default config is the heat pump map: input registers, room setpoint 41105, no shift', () {
      const config = WeishauptWemConfig();
      expect(config.host, '192.168.1.150');
      expect(config.port, 502);
      expect(config.unitId, 1);
      expect(config.multiplier, 0.1);
      expect(config.presetId, 'wem_wwp_split');
      expect(config.outdoorRegister, 30001);
      expect(config.flowRegister, 31105);
      expect(config.returnRegister, 33105);
      expect(config.hotWaterRegister, 32102);
      expect(config.roomTargetRegister, 41105);
      expect(config.heatingCurveShiftRegister, isNull);
      expect(config.isHoldingRegister, isFalse);

      final fromPreset = WeishauptWemConfig.fromPreset(WeishauptWemConfig.presets.first);
      expect(fromPreset.toJson(), config.toJson());
    });

    test('"custom" preset has no write registers', () {
      final custom = WeishauptWemConfig.fromPreset(
        WeishauptWemConfig.presets.firstWhere((p) => p.id == 'custom'),
      );
      expect(custom.roomTargetRegister, isNull);
      expect(custom.heatingCurveShiftRegister, isNull);
    });

    test('toJson and fromJson preserves all fields', () {
      const original = WeishauptWemConfig(
        presetId: 'custom',
        presetName: 'Benutzerdefiniert',
        host: '10.0.0.88',
        port: 1502,
        unitId: 2,
        outdoorRegister: 11,
        flowRegister: 12,
        returnRegister: 13,
        hotWaterRegister: 14,
        roomTargetRegister: 15,
        heatingCurveShiftRegister: 16,
        multiplier: 0.5,
        isHoldingRegister: true,
      );

      final restored = WeishauptWemConfig.fromJson(_stored(original.toJson()));
      expect(restored.toJson(), original.toJson());
    });

    for (final legacyId in ['wem_wwp_split', 'wem_biblock']) {
      test('stored $legacyId config with the invented 3101 map moves to the real map', () {
        final restored = WeishauptWemConfig.fromJson(_stored({
          'presetId': legacyId,
          'presetName': 'Weishaupt WWP LS (Split-Wärmepumpe WEM)',
          'host': '10.0.0.88',
          'port': 1502,
          'unitId': 3,
          'outdoorRegister': 3101,
          'flowRegister': 3102,
          'returnRegister': 3103,
          'hotWaterRegister': 3104,
          'roomTargetRegister': 3105,
          'heatingCurveShiftRegister': 3106,
          'multiplier': 0.1,
          'isHoldingRegister': true,
        }));

        // Connection settings survive, the register map is the new default.
        expect(restored.host, '10.0.0.88');
        expect(restored.port, 1502);
        expect(restored.unitId, 3);
        expect(restored.toJson()..removeWhere((k, _) => const {'host', 'port', 'unitId'}.contains(k)),
            const WeishauptWemConfig().toJson()..removeWhere((k, _) => const {'host', 'port', 'unitId'}.contains(k)));
      });
    }

    test('stored wem_wtc_gw config becomes a read-only custom config', () {
      final restored = WeishauptWemConfig.fromJson(_stored({
        'presetId': 'wem_wtc_gw',
        'presetName': 'Weishaupt WTC-GW (Gas-Brennwert WEM)',
        'host': '10.0.0.88',
        'unitId': 2,
        'outdoorRegister': 1,
        'flowRegister': 2,
        'returnRegister': 3,
        'hotWaterRegister': 4,
        'roomTargetRegister': 5,
        'heatingCurveShiftRegister': 6,
        'multiplier': 0.1,
        'isHoldingRegister': true,
      }));

      expect(restored.presetId, 'custom');
      expect(restored.presetName, 'Benutzerdefiniert');
      expect(restored.host, '10.0.0.88');
      expect(restored.unitId, 2);
      expect(restored.roomTargetRegister, isNull);
      expect(restored.heatingCurveShiftRegister, isNull);
      // Every stored preset id must still exist in the preset list.
      expect(WeishauptWemConfig.presets.map((p) => p.id), contains(restored.presetId));
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
      expect(loaded.outdoorRegister, 30001);
    });

    test('controller metadata and capabilities: room setpoint yes, curve shift no', () async {
      final controller = WeishauptWemController();
      expect(controller.id, 'weishaupt_wem');
      expect(controller.brandName, 'Weishaupt');
      expect(controller.protocol, ConnectionProtocol.modbusTcp);
      expect(controller.capabilities.supportsHeatingCurveShift, isFalse);
      expect(controller.capabilities.supportsRoomTarget, isTrue);
      expect(controller.capabilities.supportsHotWater, isTrue);
      expect(controller.capabilities.supportsReturnTemp, isTrue);
      expect(controller.capabilities.supportsOutdoorTemp, isTrue);
      await expectLater(controller.setHeatingCurveShift(1.0), throwsModbusError);
    });
  });

  group('NibeModbusConfig & Controller Tests', () {
    test('contains expected factory presets', () {
      expect(
        NibeModbusConfig.presets.map((p) => p.id),
        ['nibe_s_series', 'nibe_f_series_modbus40', 'nibe_smo40', 'custom'],
      );
    });

    test('default config is the S-series map: input registers 1/5/7/8, offset 30, no room register', () {
      const config = NibeModbusConfig();
      expect(config.host, '192.168.1.160');
      expect(config.port, 502);
      expect(config.unitId, 1);
      expect(config.multiplier, 0.1);
      expect(config.presetId, 'nibe_s_series');
      expect(config.outdoorRegister, 1);
      expect(config.flowRegister, 5);
      expect(config.returnRegister, 7);
      expect(config.hotWaterRegister, 8);
      expect(config.roomTargetRegister, isNull);
      expect(config.heatingCurveShiftRegister, 30);
      expect(config.isHoldingRegister, isFalse);
      expect(config.writeMultiple, isFalse);

      final fromPreset = NibeModbusConfig.fromPreset(NibeModbusConfig.presets.first);
      expect(fromPreset.toJson(), config.toJson());
    });

    test('no preset uses holding 26 (curve number) or 47007 (curve slope)', () {
      for (final preset in NibeModbusConfig.presets) {
        expect(preset.roomTargetRegister, isNull, reason: preset.id);
        expect(preset.heatingCurveShiftRegister, isIn([30, 47011]), reason: preset.id);
      }
    });

    for (final presetId in ['nibe_f_series_modbus40', 'nibe_smo40']) {
      test('$presetId maps the MODBUS 40 holding registers and writes with FC 0x10', () {
        final preset = NibeModbusConfig.presets.firstWhere((p) => p.id == presetId);
        final config = NibeModbusConfig.fromPreset(preset);

        expect(config.outdoorRegister, 40004);
        expect(config.flowRegister, 40008);
        expect(config.returnRegister, 40012);
        expect(config.hotWaterRegister, 40013);
        expect(config.roomTargetRegister, isNull);
        expect(config.heatingCurveShiftRegister, 47011);
        expect(config.isHoldingRegister, isTrue);
        expect(config.writeMultiple, isTrue);
        // Derived from the preset id, so it survives a save/load.
        expect(NibeModbusConfig.fromJson(_stored(config.toJson())).writeMultiple, isTrue);
      });
    }

    test('writeMultiple is off for the S series and custom', () {
      expect(const NibeModbusConfig().writeMultiple, isFalse);
      expect(const NibeModbusConfig(presetId: 'custom').writeMultiple, isFalse);
    });

    test('legacy F-Series config (shift=47007) is repaired on load', () {
      final legacy = NibeModbusConfig.fromJson({
        'presetId': 'nibe_f_series_modbus40',
        'roomTargetRegister': 47011,
        'heatingCurveShiftRegister': 47007,
        'isHoldingRegister': true,
      });
      expect(legacy.heatingCurveShiftRegister, 47011);
      expect(legacy.roomTargetRegister, isNull);
      expect(legacy.isHoldingRegister, isTrue);
    });

    test('legacy S-Series config (room=26, sensors as holding) is repaired on load', () {
      final legacy = NibeModbusConfig.fromJson(_stored({
        'presetId': 'nibe_s_series',
        'presetName': 'NIBE S-Serie (S1155 / S1255 / S2125 / VVM S320)',
        'host': '10.0.0.77',
        'port': 502,
        'unitId': 1,
        'outdoorRegister': 1,
        'flowRegister': 5,
        'returnRegister': 7,
        'hotWaterRegister': 8,
        'roomTargetRegister': 26,
        'heatingCurveShiftRegister': 30,
        'multiplier': 0.1,
        'isHoldingRegister': true,
      }));
      expect(legacy.host, '10.0.0.77');
      expect(legacy.roomTargetRegister, isNull);
      expect(legacy.isHoldingRegister, isFalse);
      expect(legacy.heatingCurveShiftRegister, 30);
      expect(
        [legacy.outdoorRegister, legacy.flowRegister, legacy.returnRegister, legacy.hotWaterRegister],
        [1, 5, 7, 8],
      );
    });

    test('legacy custom config loses room register 26 but keeps its own register type', () {
      final legacy = NibeModbusConfig.fromJson({
        'presetId': 'custom',
        'roomTargetRegister': 26,
        'heatingCurveShiftRegister': 30,
        'isHoldingRegister': true,
      });
      expect(legacy.roomTargetRegister, isNull);
      expect(legacy.isHoldingRegister, isTrue);
    });

    test('explicitly disabled room register stays disabled after reload', () {
      const cfg = NibeModbusConfig(roomTargetRegister: null);
      final restored = NibeModbusConfig.fromJson(cfg.toJson());
      expect(restored.roomTargetRegister, isNull);
    });

    test('toJson and fromJson preserves all fields', () {
      const original = NibeModbusConfig(
        presetId: 'custom',
        presetName: 'Benutzerdefiniert',
        host: '10.0.0.77',
        port: 1502,
        unitId: 4,
        outdoorRegister: 101,
        flowRegister: 102,
        returnRegister: 103,
        hotWaterRegister: 104,
        roomTargetRegister: 105,
        heatingCurveShiftRegister: 106,
        multiplier: 0.5,
        isHoldingRegister: true,
      );

      final restored = NibeModbusConfig.fromJson(_stored(original.toJson()));
      expect(restored.toJson(), original.toJson());
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
      expect(loaded.isHoldingRegister, isFalse);
    });

    test('controller metadata and capabilities: curve offset yes, room setpoint no', () async {
      final controller = NibeModbusController();
      expect(controller.id, 'nibe_modbus');
      expect(controller.brandName, 'NIBE');
      expect(controller.protocol, ConnectionProtocol.modbusTcp);
      expect(controller.capabilities.supportsHeatingCurveShift, isTrue);
      expect(controller.capabilities.supportsRoomTarget, isFalse);
      expect(controller.capabilities.supportsHotWater, isTrue);
      expect(controller.capabilities.supportsReturnTemp, isTrue);
      expect(controller.capabilities.supportsOutdoorTemp, isTrue);
      await expectLater(controller.setRoomTarget(21.0), throwsModbusError);
    });
  });
}
