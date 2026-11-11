import 'package:heizungstrainer/controllers/modbus_register_controller.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';

/// NIBE heat pumps via Modbus TCP.
///
/// - S series (S1155 / S1255 / S2125 / VVM S320) with built-in Modbus TCP
/// - F series and SMO 20 / 40 with the MODBUS 40 module behind an
///   RS-485-to-TCP converter (FC 0x10 writes only)
class NibeModbusController extends ModbusRegisterController {
  NibeModbusConfig _config;

  NibeModbusController({
    NibeModbusConfig? config,
    super.client,
  }) : _config = config ?? const NibeModbusConfig();

  NibeModbusConfig get config => _config;

  void updateConfig(NibeModbusConfig newConfig) {
    _config = newConfig;
  }

  @override
  String get id => 'nibe_modbus';

  @override
  String get brandName => 'NIBE';

  @override
  String get modelName => _config.presetName;

  @override
  String get deviceDative => 'zur NIBE Wärmepumpe';

  @override
  String get deviceName => 'NIBE Wärmepumpe';

  @override
  String get logTag => 'NibeModbus';

  @override
  double get minShift => -10.0;

  @override
  double get maxShift => 10.0;

  @override
  ModbusRegisterMap get registerMap => ModbusRegisterMap(
        port: _config.port,
        unitId: _config.unitId,
        outdoorRegister: _config.outdoorRegister,
        flowRegister: _config.flowRegister,
        returnRegister: _config.returnRegister,
        hotWaterRegister: _config.hotWaterRegister,
        roomTargetRegister: _config.roomTargetRegister,
        heatingCurveShiftRegister: _config.heatingCurveShiftRegister,
        multiplier: _config.multiplier,
        sensorsAreHolding: _config.isHoldingRegister,
        // NIBE offsets are whole steps (-10..10), not tenths like the temperatures.
        shiftMultiplier: 1.0,
        // MODBUS 40 (F series / SMO) only implements FC 0x10, not "write single".
        writeMultiple: _config.writeMultiple,
      );

  /// Live connection diagnostic probe for the settings UI.
  static Future<Map<String, dynamic>> testConnection(NibeModbusConfig config) =>
      NibeModbusController(config: config).probe(config.host, config.port);
}
