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

/// Danfoss ECL factory curve (Kommunikationsbeschreibung, Tabelle 6-3:
/// slope 1.0, points 75/60/50/45/40/28 °C, min 10 / max 90 °C). Many
/// installations run on it unchanged – the "most common" curve.
const ControllerHeatingCurve danfossFactoryCurve = ControllerHeatingCurve(
  outdoorTemps: [-30, -15, -5, 0, 5, 15],
  flowTemps: [75, 60, 50, 45, 40, 28],
  slope: 1.0,
  minFlow: 10,
  maxFlow: 90,
);

/// Guide values for the flow temperature by heating system and construction
/// year (EnergieSchweiz/BFE, "Betriebsoptimierung Heizung: Heizkurve
/// einstellen", 07.2022). Given at −8 °C and +15 °C outdoor for a room
/// temperature of 20 °C; linear in between, flat above +15 °C.
enum BuildingReference {
  radiatorBefore1980('Heizkörper, Baujahr vor 1980', 60, 70, 25),
  radiator1980to2000('Heizkörper, Baujahr 1980–2000', 50, 60, 25),
  radiator2000to2010('Heizkörper, Baujahr 2000–2010', 40, 50, 25),
  radiatorAfter2010('Heizkörper, Baujahr nach 2010', 35, 40, 20),
  floorUntil1990('Fußbodenheizung, Baujahr bis 1990', 35, 50, 25),
  floor1990to2010('Fußbodenheizung, Baujahr 1990–2010', 30, 40, 25),
  floorAfter2010('Fußbodenheizung, Baujahr nach 2010', 30, 35, 20);

  const BuildingReference(this.label, this.lowAtMinus8, this.highAtMinus8, this.at15);

  final String label;
  final double lowAtMinus8;
  final double highAtMinus8;
  final double at15;

  bool get isFloorHeating => name.startsWith('floor');

  static BuildingReference? fromName(String? name) {
    for (final b in values) {
      if (b.name == name) return b;
    }
    return null;
  }

  double _line(double atMinus8, double outdoor) {
    if (outdoor >= 15) return at15;
    return atMinus8 + (outdoor + 8) * (at15 - atMinus8) / 23;
  }

  /// Lower edge of the guide band at [outdoor].
  double lowAt(double outdoor) => _line(lowAtMinus8, outdoor);

  /// Upper edge of the guide band at [outdoor].
  double highAt(double outdoor) => _line(highAtMinus8, outdoor);
}
