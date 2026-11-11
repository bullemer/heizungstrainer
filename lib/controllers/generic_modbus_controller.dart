import 'package:heizungstrainer/controllers/modbus_register_controller.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';

/// Any controller with plain temperature registers on Modbus TCP.
///
/// The register map comes from the user (or a preset such as Stiebel ISG or
/// Samson TROVIS).
class GenericModbusController extends ModbusRegisterController {
  GenericModbusConfig _config;

  GenericModbusController({
    GenericModbusConfig? config,
    super.client,
  }) : _config = config ?? const GenericModbusConfig();

  GenericModbusConfig get config => _config;

  void updateConfig(GenericModbusConfig newConfig) {
    _config = newConfig;
  }

  @override
  String get id => 'generic_modbus';

  @override
  String get brandName => 'Generisch (Modbus TCP)';

  @override
  String get modelName => _config.presetName;

  @override
  String get deviceDative => 'zum Modbus-TCP-Regler';

  @override
  String get deviceName => 'Der Regler';

  @override
  String get logTag => 'GenericModbus';

  // Fragile gateways (e.g. Stiebel ISG) are asked at most every 1.5 s.
  @override
  Duration? get readThrottle => const Duration(milliseconds: 1500);

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
        wordOrder: _config.wordOrder,
        dataType: _config.dataType,
      );

  /// Live connection diagnostic probe for the settings UI.
  static Future<Map<String, dynamic>> testConnection(GenericModbusConfig config) =>
      GenericModbusController(config: config).probe(config.host, config.port);
}
