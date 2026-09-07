/// Immutable snapshot of a single parameter reading from the ECL 310 controller.
library;

import 'package:heizungstrainer/models/ecl_parameter.dart';

/// Represents a single point-in-time reading of an [ECLParameter].
///
/// Stores the raw register value as received over Modbus and provides
/// computed getters for display-unit conversion and formatting.
class ECLReading {
  /// The parameter definition this reading belongs to.
  final ECLParameter parameter;

  /// The raw int16 value as read from the Modbus holding register.
  final int rawValue;

  /// When this reading was captured.
  final DateTime timestamp;

  const ECLReading({
    required this.parameter,
    required this.rawValue,
    required this.timestamp,
  });

  /// The display-unit value after applying the parameter's multiplier.
  ///
  /// Example: raw 215 with multiplier 0.1 → 21.5
  double get displayValue => parameter.rawToDisplay(rawValue);

  /// Whether the controller reported this sensor as disconnected/faulty (code >= 19200).
  bool get isSensorDisconnected => rawValue >= ECLRegisters.sensorDisconnected;

  /// Human-readable formatted string including value and unit.
  ///
  /// Example: '21.5 °C' or '-3' (for dimensionless parameters).
  String get formattedValue {
    if (isSensorDisconnected) return 'Fühler getrennt';
    final valueStr = displayValue.toStringAsFixed(parameter.displayPrecision);
    return parameter.unit.isNotEmpty ? '$valueStr ${parameter.unit}' : valueStr;
  }

  /// Age of this reading relative to now.
  Duration get age => DateTime.now().difference(timestamp);

  /// Whether this reading is considered stale (older than 30 seconds).
  bool get isStale => age.inSeconds > 30;

  @override
  String toString() =>
      'ECLReading(${parameter.id}: $formattedValue, raw=$rawValue, '
      'age=${age.inSeconds}s)';
}
