import 'dart:async';

import 'package:heizungstrainer/controllers/heating_controller.dart';

/// Mock controller used for testing, demonstrations, or simulating other brands
/// (e.g. Viessmann, Bosch, generic Modbus).
class MockHeatingController implements HeatingController {
  @override
  final String id;
  @override
  final String brandName;
  @override
  final String modelName;
  @override
  final ConnectionProtocol protocol;
  @override
  final HeatingCapabilities capabilities;

  bool _isConnected = false;
  double _shift = 0.0;
  double _roomTarget = 20.0;
  final StreamController<ControllerTelemetry> _streamController =
      StreamController<ControllerTelemetry>.broadcast();

  MockHeatingController({
    this.id = 'mock_controller',
    this.brandName = 'Mock Brand',
    this.modelName = 'Virtual Controller 1.0',
    this.protocol = ConnectionProtocol.restApi,
    this.capabilities = const HeatingCapabilities(),
  });

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<ControllerTelemetry> get telemetryStream => _streamController.stream;

  @override
  Future<void> connect({
    required String host,
    int? port,
    Map<String, dynamic>? extraConfig,
  }) async {
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
  }

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    final telemetry = ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: 7.5,
      flowTemp: 46.0 + _shift,
      returnTemp: 36.0,
      hotWaterTemp: 52.0,
      heatingCurveShift: _shift,
      roomTarget: _roomTarget,
    );
    _streamController.add(telemetry);
    return telemetry;
  }

  @override
  Future<void> setHeatingCurveShift(double shift) async {
    _shift = shift;
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    _roomTarget = temperature;
  }
}
