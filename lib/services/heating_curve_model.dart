import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';

/// The controller's real heating curve, as read from a Danfoss ECL Comfort.
///
/// The six points give the flow temperature for a room setpoint of 20 °C. The
/// controller corrects them for other setpoints (Danfoss manual, "Heizkurve"):
///
///   Vorlauf-Korrektur = (Raumsollwert − 20) × Neigung × 2,5
///
/// and limits the result to the min./max. flow temperature.
class ControllerHeatingCurve {
  final List<double> outdoorTemps;
  final List<double> flowTemps;
  final double slope;
  final double? minFlow;
  final double? maxFlow;

  const ControllerHeatingCurve({
    required this.outdoorTemps,
    required this.flowTemps,
    required this.slope,
    this.minFlow,
    this.maxFlow,
  });

  static const double danfossRoomConstant = 2.5;
  static const double referenceRoomTemp = 20.0;

  /// Builds the curve from provider readings, or null if the controller
  /// doesn't expose all six points and the slope.
  static ControllerHeatingCurve? fromReadings(ECLReading? Function(ECLParameter) read) {
    final points = <double>[];
    for (final p in ECLRegisters.curvePoints) {
      final r = read(p);
      if (r == null) return null;
      points.add(r.displayValue);
    }
    final slope = read(ECLRegisters.curveSlope)?.displayValue;
    if (slope == null) return null;
    return ControllerHeatingCurve(
      outdoorTemps: ECLRegisters.curvePointOutdoorTemps,
      flowTemps: points,
      slope: slope,
      minFlow: read(ECLRegisters.curveMinFlow)?.displayValue,
      maxFlow: read(ECLRegisters.curveMaxFlow)?.displayValue,
    );
  }

  /// Flow-temperature change the controller applies for [roomSetpoint].
  double roomCorrection(double roomSetpoint) =>
      (roomSetpoint - referenceRoomTemp) * slope * danfossRoomConstant;

  /// Flow temperature the controller targets at [outdoor] for [roomSetpoint].
  double flowAt(double outdoor, double roomSetpoint) {
    double base;
    if (outdoor <= outdoorTemps.first) {
      base = flowTemps.first;
    } else if (outdoor >= outdoorTemps.last) {
      base = flowTemps.last;
    } else {
      var i = 0;
      while (outdoor > outdoorTemps[i + 1]) {
        i++;
      }
      final t = (outdoor - outdoorTemps[i]) / (outdoorTemps[i + 1] - outdoorTemps[i]);
      base = flowTemps[i] + t * (flowTemps[i + 1] - flowTemps[i]);
    }
    var flow = base + roomCorrection(roomSetpoint);
    if (minFlow != null && flow < minFlow!) flow = minFlow!;
    if (maxFlow != null && flow > maxFlow!) flow = maxFlow!;
    return flow;
  }
}

/// Rough savings estimate for a lower room temperature.
///
/// Uses the common rule of thumb of about 6 % heating energy per 1 °C lower
/// room temperature (e.g. co2online). It is an estimate, not a prediction for
/// a specific building.
class RoomTemperatureSavings {
  static const double percentPerKelvin = 6.0;

  final double percent;
  final double? kwhPerYear;
  final double? euroPerYear;

  const RoomTemperatureSavings({required this.percent, this.kwhPerYear, this.euroPerYear});

  /// Positive values = savings; negative = extra consumption.
  factory RoomTemperatureSavings.estimate({
    required double currentSetpoint,
    required double newSetpoint,
    double? annualHeatingKwh,
    double? pricePerKwh,
  }) {
    final percent = (currentSetpoint - newSetpoint) * percentPerKelvin;
    final kwh = annualHeatingKwh == null ? null : annualHeatingKwh * percent / 100;
    final euro = (kwh == null || pricePerKwh == null) ? null : kwh * pricePerKwh;
    return RoomTemperatureSavings(percent: percent, kwhPerYear: kwh, euroPerYear: euro);
  }
}
