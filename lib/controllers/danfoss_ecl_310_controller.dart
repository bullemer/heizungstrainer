import 'dart:async';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/services/modbus_service.dart';

/// Concrete adapter for the Danfoss ECL Comfort 310 controller via Modbus TCP.
class DanfossEcl310Controller implements HeatingController {
  final ModbusService _modbusService;
  final StreamController<ControllerTelemetry> _telemetryStreamController =
      StreamController<ControllerTelemetry>.broadcast();

  DanfossEcl310Controller({ModbusService? modbusService})
      : _modbusService = modbusService ?? ModbusService();

  @override
  String get id => 'danfoss_ecl_310';

  @override
  String get brandName => 'Danfoss';

  @override
  String get modelName => 'ECL Comfort 310';

  @override
  ConnectionProtocol get protocol => ConnectionProtocol.modbusTcp;

  @override
  HeatingCapabilities get capabilities => const HeatingCapabilities(
        supportsHeatingCurveShift: true,
        minShift: -15.0,
        maxShift: 15.0,
        supportsRoomTarget: true,
        minRoomTarget: 5.0,
        maxRoomTarget: 30.0,
        supportsHotWater: true,
        supportsReturnTemp: true,
        supportsOutdoorTemp: true,
      );

  @override
  bool get isConnected => _modbusService.isConnected;

  @override
  Stream<ControllerTelemetry> get telemetryStream =>
      _telemetryStreamController.stream;

  @override
  Future<void> connect({
    required String host,
    int? port,
    Map<String, dynamic>? extraConfig,
  }) async {
    await _modbusService.connect(host, port: port ?? 502);
  }

  @override
  Future<void> disconnect() async {
    _modbusService.disconnect();
  }

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    final readings = await _modbusService.readAllParameters();
    final now = DateTime.now();

    final outdoor = readings[ECLRegisters.outdoorTemp.id];
    final flow = readings[ECLRegisters.flowTemp.id];
    final ret = readings[ECLRegisters.returnTemp.id];
    final hw = readings[ECLRegisters.hotWaterTemp.id];
    final shift = readings[ECLRegisters.heatingCurveShift.id];
    final room = readings[ECLRegisters.roomTargetTemp.id];

    final telemetry = ControllerTelemetry(
      timestamp: now,
      outdoorTemp: (outdoor != null && !outdoor.isSensorDisconnected)
          ? outdoor.displayValue
          : null,
      flowTemp: (flow != null && !flow.isSensorDisconnected)
          ? flow.displayValue
          : null,
      returnTemp: (ret != null && !ret.isSensorDisconnected)
          ? ret.displayValue
          : null,
      hotWaterTemp: (hw != null && !hw.isSensorDisconnected)
          ? hw.displayValue
          : null,
      heatingCurveShift: shift?.displayValue,
      roomTarget: room?.displayValue,
      isOutdoorDisconnected: outdoor?.isSensorDisconnected ?? false,
      isFlowDisconnected: flow?.isSensorDisconnected ?? false,
      rawValues: {
        for (final entry in readings.entries) entry.key: entry.value.displayValue,
      },
    );

    _telemetryStreamController.add(telemetry);
    return telemetry;
  }

  @override
  Future<void> setHeatingCurveShift(double shift) async {
    await _modbusService.writeAndVerify(ECLRegisters.heatingCurveShift, shift);
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    await _modbusService.writeAndVerify(ECLRegisters.roomTargetTemp, temperature);
  }
}
