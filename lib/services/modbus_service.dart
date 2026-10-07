/// Low-level Modbus TCP communication service for the Danfoss ECL 310 controller.
///
/// Handles connection lifecycle, register reads, and safety-validated writes.
/// All write operations pass through strict bounds checking before any
/// Modbus frame is compiled and transmitted.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';

/// Core Modbus TCP service for reading sensor values and safely writing
/// setpoints to the ECL 310 heating controller.
///
/// ## Safety Architecture
///
/// Every write operation follows a strict three-stage validation pipeline:
/// 1. **Writability check** — reject read-only parameters.
/// 2. **Bounds validation** — reject values outside the parameter's
///    hardcoded `[minValue, maxValue]` range.
/// 3. **Transmission** — only after both checks pass is the Modbus
///    write frame compiled and sent.
class ModbusService {
  static const Duration _requestTimeout = Duration(seconds: 5);

  ModbusClientTcp? _client;
  String? _currentIp;
  bool _isConnected = false;

  /// Whether the service currently has an active connection.
  bool get isConnected => _isConnected;

  /// The IP address of the currently connected controller, or `null`.
  String? get currentIp => _currentIp;

  // ──────────────────────────────────────────────────────────────────
  // Connection Lifecycle
  // ──────────────────────────────────────────────────────────────────

  /// Establishes a Modbus TCP connection to the ECL controller at [ip].
  ///
  /// If already connected to a different IP, the existing connection
  /// is cleanly torn down first.
  ///
  /// Throws [ModbusCommunicationException] on failure.
  Future<void> connect(String ip, {int port = 502}) async {
    // Disconnect existing connection when switching targets
    if (_currentIp != null && _currentIp != ip) {
      await disconnect();
    }

    _client = ModbusClientTcp(
      ip,
      serverPort: port,
      unitId: 1,
      connectionMode: ModbusConnectionMode.autoConnectAndKeepConnected,
    );
    _currentIp = ip;

    try {
      final connected = await _client!.connect();
      _isConnected = connected;
      debugPrint('[Modbus] Connected to $ip: $connected');
      if (!connected) {
        throw ModbusCommunicationException(
          message: 'Verbindung zum ECL-Regler unter $ip konnte nicht hergestellt werden.',
        );
      }
    } catch (e) {
      if (e is ModbusCommunicationException) rethrow;
      _isConnected = false;
      _client = null;
      _currentIp = null;
      throw ModbusCommunicationException(
        message: 'Verbindung zum ECL-Regler unter $ip fehlgeschlagen.',
        underlyingError: e,
      );
    }
  }

  /// Disconnects from the controller and releases all resources.
  Future<void> disconnect() async {
    try {
      await _client?.disconnect();
    } catch (_) {}
    _client = null;
    _isConnected = false;
    _currentIp = null;
  }

  /// Asserts that a connection is active. Throws if not.
  void _ensureConnected() {
    if (_client == null || !_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum ECL-Regler. '
            'Bitte zuerst verbinden.',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Reading
  // ──────────────────────────────────────────────────────────────────

  /// Reads a single [parameter] from the connected controller.
  ///
  /// Returns an [ECLReading] with the raw value and timestamp.
  /// Throws [ModbusCommunicationException] on failure or timeout.
  /// ECL alarm bitmask as one 32-bit value (bit 0 = alarm 1 … bit 31 =
  /// alarm 32), or null if the application doesn't provide it.
  Future<int?> readAlarmMask() async {
    try {
      final high = await readParameter(ECLRegisters.alarmMaskHigh);
      final low = await readParameter(ECLRegisters.alarmMaskLow);
      return ((high.rawValue & 0xFFFF) << 16) | (low.rawValue & 0xFFFF);
    } catch (e) {
      debugPrint('[Modbus] Alarm registers not available: $e');
      return null;
    }
  }

  /// Installed application, e.g. "A266.1 v1.08", or null if not readable.
  Future<String?> readApplicationName() async {
    try {
      final v = [for (final p in ECLRegisters.applicationInfo) (await readParameter(p)).rawValue & 0xFFFF];
      final version = '${v[3] >> 8}.${(v[3] & 0xFF).toString().padLeft(2, '0')}';
      return '${String.fromCharCode(v[0])}${v[1]}.${v[2]} v$version';
    } catch (e) {
      debugPrint('[Modbus] Application info not available: $e');
      return null;
    }
  }

  Future<ECLReading> readParameter(ECLParameter parameter) async {
    _ensureConnected();

    // Create register without multiplier — we handle conversion in ECLParameter
    final register = ModbusInt16Register(
      name: parameter.id,
      type: ModbusElementType.holdingRegister,
      address: parameter.modbusAddress,
    );

    try {
      final response = await _client!
          .send(register.getReadRequest())
          .timeout(_requestTimeout);

      debugPrint('[Modbus] Read ${parameter.id}: response=$response, value=${register.value} (${register.value.runtimeType})');

      if (response != ModbusResponseCode.requestSucceed) {
        throw ModbusCommunicationException(
          message: 'Lesefehler für ${parameter.name}: '
              'Modbus-Fehlercode $response',
        );
      }

      final rawValue = register.value;
      if (rawValue == null) {
        throw ModbusCommunicationException(
          message: 'Kein Wert empfangen für ${parameter.name}.',
        );
      }

      return ECLReading(
        parameter: parameter,
        rawValue: rawValue.toInt(),
        timestamp: DateTime.now(),
      );
    } on TimeoutException {
      throw ModbusCommunicationException(
        message: 'Zeitüberschreitung beim Lesen von ${parameter.name}.',
      );
    } catch (e) {
      if (e is ModbusCommunicationException) rethrow;
      throw ModbusCommunicationException(
        message: 'Fehler beim Lesen von ${parameter.name}.',
        underlyingError: e,
      );
    }
  }

  /// Reads all sensor parameters in a single batch Modbus request (registers 10200..10205).
  Future<Map<String, ECLReading>> _readSensorBatch() async {
    final registers = {
      for (final param in ECLRegisters.sensorParameters)
        param: ModbusInt16Register(
          name: param.id,
          type: ModbusElementType.holdingRegister,
          address: param.modbusAddress,
        ),
    };

    final group = ModbusElementsGroup(registers.values);
    final response = await _client!
        .send(group.getReadRequest())
        .timeout(_requestTimeout);

    if (response != ModbusResponseCode.requestSucceed) {
      throw ModbusCommunicationException(
        message: 'Gruppenlesefehler: Modbus-Code $response',
      );
    }

    final now = DateTime.now();
    final results = <String, ECLReading>{};
    for (final entry in registers.entries) {
      final val = entry.value.value;
      if (val != null) {
        results[entry.key.id] = ECLReading(
          parameter: entry.key,
          rawValue: val.toInt(),
          timestamp: now,
        );
      }
    }
    return results;
  }

  /// Reads all registered parameters.
  ///
  /// Uses a single batch request for sensors (registers 10200..10205) to reduce
  /// network roundtrips by 80%, with automatic fallback to individual reads.
  /// If an individual parameter read fails, other successful readings are preserved.
  Future<Map<String, ECLReading>> readAllParameters() async {
    _ensureConnected();
    final results = <String, ECLReading>{};
    int failureCount = 0;
    Object? lastError;

    // 1. Batch-read sensor parameters in 1 network roundtrip
    try {
      final sensorReadings = await _readSensorBatch();
      results.addAll(sensorReadings);
      debugPrint('[Modbus] Batch-read ${sensorReadings.length} sensors in 1 request.');
    } catch (e) {
      debugPrint('[Modbus] Sensor batch-read failed, falling back to sequential: $e');
      for (final param in ECLRegisters.sensorParameters) {
        try {
          results[param.id] = await readParameter(param);
        } catch (err) {
          failureCount++;
          lastError = err;
          debugPrint('[Modbus] Failed reading sensor ${param.id}: $err');
        }
      }
    }

    // 2. Read writable setpoints
    for (final param in ECLRegisters.writableParameters) {
      try {
        results[param.id] = await readParameter(param);
      } catch (err) {
        failureCount++;
        lastError = err;
        debugPrint('[Modbus] Failed reading setpoint ${param.id}: $err');
      }
    }

    // 3. Optional heating-curve parameters (not every application has them;
    //    a missing one is not a connection problem).
    for (final param in [...ECLRegisters.curveParameters, ...ECLRegisters.extraSettings]) {
      try {
        results[param.id] = await readParameter(param);
      } catch (err) {
        debugPrint('[Modbus] Curve parameter ${param.id} not available: $err');
      }
    }

    // If every single parameter failed to read, the connection is broken
    if (results.isEmpty && failureCount > 0) {
      if (lastError is ModbusCommunicationException) throw lastError;
      throw ModbusCommunicationException(
        message: 'Keine Parameter vom ECL-Regler lesbar.',
        underlyingError: lastError,
      );
    }

    return results;
  }

  // ──────────────────────────────────────────────────────────────────
  // Writing (with Fail-Safe Validation)
  // ──────────────────────────────────────────────────────────────────

  /// Safely writes a display-unit [displayValue] to a writable [parameter].
  ///
  /// ## Safety Pipeline
  /// 1. **Writability gate**: Rejects read-only parameters immediately.
  /// 2. **Bounds gate**: Validates [displayValue] against the parameter's
  ///    `[minValue, maxValue]` range. On violation, throws
  ///    [ParameterBoundsException] **before** any Modbus I/O occurs.
  /// 3. **Transmission**: Converts to raw value and sends the write command.
  Future<void> writeParameter(
    ECLParameter parameter,
    double displayValue,
  ) async {
    _ensureConnected();

    // ── SAFETY CHECK 1: Writability ──────────────────────────────
    if (!parameter.isWritable) {
      throw ModbusCommunicationException(
        message: '${parameter.name} ist schreibgeschützt und kann '
            'nicht verändert werden.',
      );
    }

    // ── SAFETY CHECK 2: Bounds validation (BEFORE any Modbus I/O) ──
    final validationError = parameter.validateDisplayValue(displayValue);
    if (validationError != null) {
      throw ParameterBoundsException(
        parameter: parameter,
        attemptedValue: displayValue,
      );
    }

    // ── Convert display → raw ────────────────────────────────────
    final rawValue = parameter.displayToRaw(displayValue);
    debugPrint('[Modbus] Writing ${parameter.id}: display=$displayValue → raw=$rawValue');

    // ── SAFETY CHECK 3: Transmit ─────────────────────────────────
    final register = ModbusInt16Register(
      name: parameter.id,
      type: ModbusElementType.holdingRegister,
      address: parameter.modbusAddress,
    );

    try {
      final response = await _client!
          .send(register.getWriteRequest(rawValue))
          .timeout(_requestTimeout);

      debugPrint('[Modbus] Write response for ${parameter.id}: $response');

      if (response != ModbusResponseCode.requestSucceed) {
        throw ModbusCommunicationException(
          message: 'Schreibfehler für ${parameter.name}: '
              'Modbus-Fehlercode $response',
        );
      }
    } on TimeoutException {
      throw ModbusCommunicationException(
        message: 'Zeitüberschreitung beim Schreiben von ${parameter.name}.',
      );
    } catch (e) {
      if (e is ModbusCommunicationException ||
          e is ParameterBoundsException) {
        rethrow;
      }
      throw ModbusCommunicationException(
        message: 'Fehler beim Schreiben von ${parameter.name}.',
        underlyingError: e,
      );
    }
  }

  /// Writes a value and immediately reads it back for verification.
  Future<ECLReading> writeAndVerify(
    ECLParameter parameter,
    double displayValue,
  ) async {
    await writeParameter(parameter, displayValue);
    // Brief delay to let the controller process the write
    await Future.delayed(const Duration(milliseconds: 200));
    return readParameter(parameter);
  }
}
