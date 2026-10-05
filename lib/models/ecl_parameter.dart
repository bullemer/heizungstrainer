/// Data model representing a single Modbus register parameter
/// for the Danfoss ECL Comfort 310 controller.
library;

/// A single ECL 310 controller register definition.
class ECLParameter {
  final String id;
  final String name;
  final String unit;
  final int modbusAddress;
  final double multiplier;
  final bool isWritable;
  final double? minValue;
  final double? maxValue;

  const ECLParameter({
    required this.id,
    required this.name,
    required this.unit,
    required this.modbusAddress,
    required this.multiplier,
    this.isWritable = false,
    this.minValue,
    this.maxValue,
  });

  double rawToDisplay(int rawValue) => rawValue * multiplier;
  int displayToRaw(double displayValue) => (displayValue / multiplier).round();

  String? validateDisplayValue(double value) {
    if (!isWritable) return '$name is read-only.';
    if (minValue != null && value < minValue!) {
      return 'Wert $value unter Minimum $minValue für $name.';
    }
    if (maxValue != null && value > maxValue!) {
      return 'Wert $value über Maximum $maxValue für $name.';
    }
    return null;
  }

  int get displayPrecision {
    if (multiplier <= 0.01) return 1;
    if (multiplier < 1) return 1;
    return 0;
  }

  @override
  String toString() => 'ECLParameter($id: addr=$modbusAddress)';
}

/// Static registry of all known ECL 310 controller parameters.
///
/// Addresses follow the Danfoss "ECL Comfort 210/296/310
/// Kommunikationsbeschreibung" (AQ074886472234de): Modbus register address =
/// parameter number (PNU) − 1. Circuit 1 shown; circuit 2 is PNU + 1000.
/// Which sensor is flow/return depends on the application key – check the
/// installation's manual when adding new parameters.
abstract final class ECLRegisters {
  static const int sensorDisconnected = 19200;

  // ── Read-Only Sensors (10200+ range, scale ×0.01) ──────────────

  /// S1 Outdoor temp. Addr 10200. Raw×0.01 = °C.
  static const outdoorTemp = ECLParameter(
    id: 'outdoor_temp',
    name: 'Außentemperatur',
    unit: '°C',
    modbusAddress: 10200,
    multiplier: 0.01,
  );

  /// S2/S3 Flow temp (Vorlauf). Addr 10203. Raw×0.01 = °C.
  static const flowTemp = ECLParameter(
    id: 'flow_temp',
    name: 'Vorlauftemperatur',
    unit: '°C',
    modbusAddress: 10203,
    multiplier: 0.01,
  );

  /// Return temp (Rücklauf). Addr 10202. Raw×0.01 = °C.
  static const returnTemp = ECLParameter(
    id: 'return_temp',
    name: 'Rücklauftemperatur',
    unit: '°C',
    modbusAddress: 10202,
    multiplier: 0.01,
  );

  /// S5 sensor. Addr 10204. Raw×0.01 = °C.
  static const sensor5 = ECLParameter(
    id: 'sensor_5',
    name: 'Sensor S5',
    unit: '°C',
    modbusAddress: 10204,
    multiplier: 0.01,
  );

  /// S6 Hot water tank upper temp. Addr 10205. Raw×0.01 = °C.
  /// Probed value: 5418 → 54.18°C (plausible hot water tank).
  static const hotWaterTemp = ECLParameter(
    id: 'hot_water_temp',
    name: 'Warmwasser-Speicher',
    unit: '°C',
    modbusAddress: 10205,
    multiplier: 0.01,
  );

  // ── Read/Write Setpoints (11xxx range) ─────────────────────────

  /// Heating curve parallel shift ("Verschieben"), PNU 11176 → register 11175.
  /// Integer, no scaling. UI-limited to -3 to +3.
  ///
  /// Up to 1.1.3 this pointed at register 11112 (= PNU 11113, the filter
  /// constant of the flow/energy limitation), not the curve shift.
  static const heatingCurveShift = ECLParameter(
    id: 'heating_curve_shift',
    name: 'Heizkurven-Parallelverschiebung',
    unit: '',
    modbusAddress: 11175,
    multiplier: 1.0,
    isWritable: true,
    minValue: -15,
    maxValue: 15,
  );

  /// Comfort room setpoint ("Komfort-Raumsollwert"), PNU 11180 → register
  /// 11179. Raw×0.1 = °C. (Up to 1.1.3: register 11003 = PNU 11004 "Gew. Temp.".)
  static const roomTargetTemp = ECLParameter(
    id: 'room_target_temp',
    name: 'Raum-Solltemperatur',
    unit: '°C',
    modbusAddress: 11179,
    multiplier: 0.1,
    isWritable: true,
    minValue: 5.0,
    maxValue: 30.0,
  );

  // ── Heating curve, circuit 1 (read-only here) ─────────────────
  // PNU 11175 slope (×0.1), 11177/11178 min/max flow, 11400–11405 the six
  // flow-temperature points at -30/-15/-5/0/5/15 °C outdoor, all for a room
  // setpoint of 20 °C (Danfoss Kommunikationsbeschreibung, Tabelle 6-3).

  static const curveSlope = ECLParameter(
    id: 'curve_slope', name: 'Heizkurve (Neigung)', unit: '',
    modbusAddress: 11174, multiplier: 0.1,
  );
  static const curveMinFlow = ECLParameter(
    id: 'curve_min_flow', name: 'Min. Vorlauftemperatur', unit: '°C',
    modbusAddress: 11176, multiplier: 1.0,
  );
  static const curveMaxFlow = ECLParameter(
    id: 'curve_max_flow', name: 'Max. Vorlauftemperatur', unit: '°C',
    modbusAddress: 11177, multiplier: 1.0,
  );

  /// "Sommer-Aus": outdoor temperature above which the circuit stops heating.
  static const summerCutoff = ECLParameter(
    id: 'summer_cutoff', name: 'Sommer-Aus', unit: '°C',
    modbusAddress: 11178, multiplier: 1.0,
  );

  /// Outdoor temperatures of the six curve points, in register order.
  static const List<double> curvePointOutdoorTemps = [-30, -15, -5, 0, 5, 15];

  static const List<ECLParameter> curvePoints = [
    ECLParameter(id: 'curve_point_m30', name: 'Vorlauf bei -30 °C', unit: '°C', modbusAddress: 11399, multiplier: 1.0),
    ECLParameter(id: 'curve_point_m15', name: 'Vorlauf bei -15 °C', unit: '°C', modbusAddress: 11400, multiplier: 1.0),
    ECLParameter(id: 'curve_point_m5', name: 'Vorlauf bei -5 °C', unit: '°C', modbusAddress: 11401, multiplier: 1.0),
    ECLParameter(id: 'curve_point_0', name: 'Vorlauf bei 0 °C', unit: '°C', modbusAddress: 11402, multiplier: 1.0),
    ECLParameter(id: 'curve_point_p5', name: 'Vorlauf bei 5 °C', unit: '°C', modbusAddress: 11403, multiplier: 1.0),
    ECLParameter(id: 'curve_point_p15', name: 'Vorlauf bei 15 °C', unit: '°C', modbusAddress: 11404, multiplier: 1.0),
  ];

  /// Optional curve parameters; not every application provides them.
  static const List<ECLParameter> curveParameters = [
    curveSlope,
    curveMinFlow,
    curveMaxFlow,
    summerCutoff,
    ...curvePoints,
  ];

  /// All registered parameters.
  static const List<ECLParameter> all = [
    outdoorTemp,
    flowTemp,
    returnTemp,
    hotWaterTemp,
    heatingCurveShift,
    roomTargetTemp,
    ...curveParameters,
  ];

  static const List<ECLParameter> writableParameters = [
    heatingCurveShift,
    roomTargetTemp,
  ];

  static const List<ECLParameter> sensorParameters = [
    outdoorTemp,
    flowTemp,
    returnTemp,
    hotWaterTemp,
  ];
}
