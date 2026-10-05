/// Custom exception types for the Heizungstrainer application.
///
/// These exceptions provide structured, UI-friendly error information
/// for Modbus communication failures, safety violations, and discovery issues.
library;

import 'package:heizungstrainer/models/ecl_parameter.dart';

/// Thrown when a write value violates a parameter's hardcoded safety bounds.
///
/// This is the primary fail-safe mechanism: it prevents any out-of-range
/// value from ever being compiled into a Modbus write frame.
class ParameterBoundsException implements Exception {
  /// The parameter whose bounds were violated.
  final ECLParameter parameter;

  /// The value that was attempted.
  final double attemptedValue;

  ParameterBoundsException({
    required this.parameter,
    required this.attemptedValue,
  });

  /// Human-readable error message for UI display.
  String get message {
    final min = parameter.minValue;
    final max = parameter.maxValue;
    final unit = parameter.unit.isNotEmpty ? ' ${parameter.unit}' : '';
    return 'Wert ${attemptedValue.toStringAsFixed(parameter.displayPrecision)}$unit '
        'liegt außerhalb des erlaubten Bereichs '
        '[${min?.toStringAsFixed(parameter.displayPrecision) ?? '−∞'}, '
        '${max?.toStringAsFixed(parameter.displayPrecision) ?? '+∞'}] '
        'für ${parameter.name}.';
  }

  @override
  String toString() => 'ParameterBoundsException: $message';
}

/// Thrown when Modbus TCP communication fails.
///
/// Wraps underlying socket/protocol errors with a user-facing message.
class ModbusCommunicationException implements Exception {
  /// User-facing error description.
  final String message;

  /// The original error/exception, if available.
  final Object? underlyingError;

  const ModbusCommunicationException({
    required this.message,
    this.underlyingError,
  });

  @override
  String toString() {
    final base = 'ModbusCommunicationException: $message';
    return underlyingError != null ? '$base (caused by: $underlyingError)' : base;
  }
}

/// Thrown when network discovery fails to locate an ECL 310 controller.
class ControllerNotFoundException implements Exception {
  /// The subnet that was scanned (e.g., '192.168.1.0/24').
  final String subnet;

  /// User-facing error description.
  final String message;

  const ControllerNotFoundException({
    required this.subnet,
    required this.message,
  });

  @override
  String toString() => 'ControllerNotFoundException: $message (subnet: $subnet)';
}

/// Text to show the user for an error from a controller operation: the plain
/// message for our own exceptions, [fallback] for anything unexpected.
String userFacingError(Object error, {String fallback = 'Unbekannter Fehler.'}) {
  if (error is ModbusCommunicationException) return error.message;
  if (error is ParameterBoundsException) return error.message;
  final text = error.toString();
  return text.startsWith('Instance of') ? fallback : text;
}
