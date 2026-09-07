import 'dart:async';

/// Supported communication protocols for heating controllers.
enum ConnectionProtocol {
  modbusTcp,
  modbusRtu,
  restApi,
  mqtt,
  eBus,
  proprietary,
}

/// Declares the physical and logical capabilities of a heating controller.
class HeatingCapabilities {
  /// Whether the controller supports adjusting the heating curve parallel shift.
  final bool supportsHeatingCurveShift;
  final double minShift;
  final double maxShift;

  /// Whether the controller supports adjusting the room target temperature.
  final bool supportsRoomTarget;
  final double minRoomTarget;
  final double maxRoomTarget;

  /// Whether the controller monitors domestic hot water (Warmwasserspeicher).
  final bool supportsHotWater;

  /// Whether the controller provides return temperature (Rücklauftemperatur).
  final bool supportsReturnTemp;

  /// Whether the controller provides outdoor temperature (Außentemperatur).
  final bool supportsOutdoorTemp;

  const HeatingCapabilities({
    this.supportsHeatingCurveShift = true,
    this.minShift = -15.0,
    this.maxShift = 15.0,
    this.supportsRoomTarget = true,
    this.minRoomTarget = 5.0,
    this.maxRoomTarget = 30.0,
    this.supportsHotWater = true,
    this.supportsReturnTemp = true,
    this.supportsOutdoorTemp = true,
  });
}

/// Normalized telemetry snapshot read from any heating controller.
class ControllerTelemetry {
  final DateTime timestamp;
  final double? outdoorTemp;
  final double? flowTemp;
  final double? returnTemp;
  final double? hotWaterTemp;
  final double? heatingCurveShift;
  final double? roomTarget;
  final bool isOutdoorDisconnected;
  final bool isFlowDisconnected;
  final Map<String, double> rawValues;

  const ControllerTelemetry({
    required this.timestamp,
    this.outdoorTemp,
    this.flowTemp,
    this.returnTemp,
    this.hotWaterTemp,
    this.heatingCurveShift,
    this.roomTarget,
    this.isOutdoorDisconnected = false,
    this.isFlowDisconnected = false,
    this.rawValues = const {},
  });

  /// The temperature differential (Spreizung = Vorlauf - Rücklauf).
  double? get spread => (flowTemp != null && returnTemp != null)
      ? (flowTemp! - returnTemp!)
      : null;
}

/// Abstract interface that all heating controller adapters must implement.
abstract class HeatingController {
  /// Unique identifier of this controller implementation (e.g. 'danfoss_ecl_310').
  String get id;

  /// Human-readable brand name (e.g. 'Danfoss', 'Viessmann', 'Bosch').
  String get brandName;

  /// Human-readable model designation (e.g. 'ECL Comfort 310', 'Vitotronic 200').
  String get modelName;

  /// Primary protocol used for communication.
  ConnectionProtocol get protocol;

  /// The feature set supported by this controller.
  HeatingCapabilities get capabilities;

  /// Whether a connection is currently established.
  bool get isConnected;

  /// Stream of periodic telemetry updates.
  Stream<ControllerTelemetry> get telemetryStream;

  /// Connects to the controller using target-specific parameters (IP, port, token, etc.).
  Future<void> connect({
    required String host,
    int? port,
    Map<String, dynamic>? extraConfig,
  });

  /// Disconnects from the controller.
  Future<void> disconnect();

  /// Reads a single, fresh telemetry snapshot from the controller.
  Future<ControllerTelemetry> readTelemetry();

  /// Sets the heating curve parallel shift (if supported).
  Future<void> setHeatingCurveShift(double shift);

  /// Sets the room target temperature (if supported).
  Future<void> setRoomTarget(double temperature);
}
