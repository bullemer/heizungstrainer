import 'package:heizungstrainer/controllers/modbus_register_controller.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';

/// Weishaupt heat pumps (WWP LS / LB, Biblock) via the Modbus TCP interface
/// of the WEM system.
class WeishauptWemController extends ModbusRegisterController {
  WeishauptWemConfig _config;

  WeishauptWemController({
    WeishauptWemConfig? config,
    super.client,
  }) : _config = config ?? const WeishauptWemConfig();

  WeishauptWemConfig get config => _config;

  void updateConfig(WeishauptWemConfig newConfig) {
    _config = newConfig;
  }

  @override
  String get id => 'weishaupt_wem';

  @override
  String get brandName => 'Weishaupt';

  @override
  String get modelName => _config.presetName;

  @override
  String get deviceDative => 'zur Weishaupt WEM';

  @override
  String get deviceName => 'Weishaupt WEM';

  @override
  String get logTag => 'WeishauptWem';

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
      );

  /// Live connection diagnostic probe for the settings UI.
  static Future<Map<String, dynamic>> testConnection(WeishauptWemConfig config) =>
      WeishauptWemController(config: config).probe(config.host, config.port);
}
