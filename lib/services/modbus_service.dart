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
import 'package:heizungstrainer/models/controller_holiday.dart';
import 'package:heizungstrainer/models/live_snapshot.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
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
  /// Per-application sensor registers (parameter id → address), set by the
  /// provider once the controller's application is known.
  Map<String, int> sensorAddressOverrides = const {};

  /// Application-specific extra sensors read on every poll (e.g. A247 S4/S8).
  List<ECLParameter> extraSensors = const [];

  /// The sensor parameters at the registers this installation uses.
  List<ECLParameter> get _sensorParameters => [
        for (final p in ECLRegisters.sensorParameters)
          sensorAddressOverrides.containsKey(p.id) ? p.atAddress(sensorAddressOverrides[p.id]!) : p,
      ];

  /// Reads [count] raw holding registers starting at [address] in one request.
  Future<List<int>> _readRaw(int address, int count) async {
    _ensureConnected();
    final regs = [
      for (var i = 0; i < count; i++)
        ModbusInt16Register(name: 'r${address + i}', type: ModbusElementType.holdingRegister, address: address + i),
    ];
    final response = await _client!.send(ModbusElementsGroup(regs).getReadRequest()).timeout(_requestTimeout);
    if (response != ModbusResponseCode.requestSucceed) {
      throw ModbusCommunicationException(message: 'Lesefehler Register $address (+$count): Modbus-Code $response');
    }
    return [for (final r in regs) (r.value ?? 0).toInt()];
  }

  /// Weekly comfort schedule of heating circuit 1, or null if the
  /// application has none.
  Future<WeekSchedule?> readSchedule({int basePnu = WeekSchedule.heatingBasePnu}) async {
    try {
      return WeekSchedule.fromRaw([
        for (var day = 0; day < 7; day++) await _readRaw(WeekSchedule.address(day, 0, stop: false, basePnu: basePnu), 6),
      ]);
    } catch (e) {
      debugPrint('[Modbus] Schedule not available: $e');
      return null;
    }
  }

  /// Writes the three periods of [day] (P1 start, P1 stop, … in this order,
  /// as the Danfoss description requires) and returns the schedule read back.
  Future<WeekSchedule?> writeScheduleDay(int day, List<SchedulePeriod> periods,
      {int basePnu = WeekSchedule.heatingBasePnu}) async {
    _ensureConnected();
    if (periods.length != 3) throw ArgumentError('3 periods expected');
    final valid = {for (var h = 0; h <= 24; h++) ...[h * 100, if (h < 24) h * 100 + 30]};
    for (var p = 0; p < 3; p++) {
      for (final (value, stop) in [(periods[p].start, false), (periods[p].stop, true)]) {
        if (!valid.contains(value)) {
          throw ModbusCommunicationException(message: 'Ungültige Uhrzeit $value im Zeitprogramm.');
        }
        final address = WeekSchedule.address(day, p, stop: stop, basePnu: basePnu);
        final register = ModbusInt16Register(name: 's$address', type: ModbusElementType.holdingRegister, address: address);
        final response = await _client!.send(register.getWriteRequest(value)).timeout(_requestTimeout);
        if (response != ModbusResponseCode.requestSucceed) {
          throw ModbusCommunicationException(message: 'Schreibfehler Zeitprogramm (Register $address): Modbus-Code $response');
        }
      }
    }
    await Future.delayed(const Duration(milliseconds: 200));
    return readSchedule(basePnu: basePnu);
  }

  Future<int?> _readOne(int address) async {
    try {
      return (await _readRaw(address, 1)).first;
    } catch (_) {
      return null;
    }
  }

  /// Everything the plant diagram needs, in a few requests: sensors S1–S10,
  /// the application's sensor references, outputs, circuit mode/status,
  /// limiter flags and the controller clock. Read only while the live view
  /// is open.
  Future<LiveSnapshot> readLiveSnapshot(LiveViewSpec spec) async {
    final rawSensors = await _readRaw(10200, 10);
    final sensors = {for (var i = 0; i < 10; i++) i + 1: LiveSnapshot.sensorFromRaw(rawSensors[i])};
    final references = <int, double>{};
    for (final e in spec.references.entries) {
      final v = await _readOne(LiveViewSpec.referenceAddress(e.value, e.key));
      if (v != null && v < 19200) references[e.key] = v / 100.0;
    }
    List<bool> bits(List<int> raw) => [for (final v in raw) v != 0];
    final outputs = await _readRaw(3999, 12); // Tr1–Tr6, R1–R6
    final mode = await _readRaw(4200, 2).catchError((_) => <int>[]);
    final status = await _readRaw(4210, 2).catchError((_) => <int>[]);
    final limiter = await _readRaw(4219, 4).catchError((_) => <int>[]);
    final clock = await _readRaw(64044, 5).catchError((_) => <int>[]);
    DateTime? time;
    if (clock.length == 5) {
      try {
        time = DateTime(clock[4], clock[3], clock[2], clock[0], clock[1]);
      } catch (_) {}
    }
    return LiveSnapshot(
      at: DateTime.now(),
      spec: spec,
      sensors: sensors,
      references: references,
      triacs: bits(outputs.sublist(0, 6)),
      relays: bits(outputs.sublist(6, 12)),
      circuitMode: {for (var i = 0; i < mode.length; i++) i + 1: mode[i]},
      circuitStatus: {for (var i = 0; i < status.length; i++) i + 1: status[i]},
      limiter: [for (final v in limiter) v & 0xFFFF],
      controllerTime: time,
    );
  }

  /// All holiday schedules (P1–P12) of the controller; stops at the first
  /// schedule the application doesn't have.
  Future<List<ControllerHolidayEntry>> readHolidaySchedules({int max = 12}) async {
    final out = <ControllerHolidayEntry>[];
    for (var slot = 1; slot <= max; slot++) {
      try {
        out.add(ControllerHolidayEntry.fromRaw(slot, await _readRaw(ControllerHolidayEntry.address(slot, 0), 7)));
      } catch (e) {
        // only "register does not exist" ends the list; timeouts etc. must
        // surface, or callers would think the schedules are empty
        if (e.toString().contains('illegalDataAddress')) break;
        rethrow;
      }
    }
    return out;
  }

  /// Writes one holiday schedule: dates first (year, month, day – a day
  /// value is always valid for the old month), the mode last, as the Danfoss
  /// description requires. Returns the schedule read back.
  Future<ControllerHolidayEntry> writeHolidaySchedule(
    int slot, {
    required ControllerHolidayMode mode,
    required DateTime start,
    required DateTime end,
  }) async {
    _ensureConnected();
    Future<void> write(int index, int value) async {
      final address = ControllerHolidayEntry.address(slot, index);
      final register = ModbusInt16Register(name: 'h$address', type: ModbusElementType.holdingRegister, address: address);
      final response = await _client!.send(register.getWriteRequest(value)).timeout(_requestTimeout);
      if (response != ModbusResponseCode.requestSucceed) {
        throw ModbusCommunicationException(message: 'Schreibfehler Urlaubsprogramm P$slot (Register $address): Modbus-Code $response');
      }
    }

    if (mode != ControllerHolidayMode.off) {
      // switch the schedule off first so no half-written period can be active,
      // then day 1 (valid in every month) before year/month, the day last
      await write(0, ControllerHolidayMode.off.code);
      for (final (dayIndex, date) in [(1, start), (4, end)]) {
        await write(dayIndex, 1);
        await write(dayIndex + 2, date.year);
        await write(dayIndex + 1, date.month);
        await write(dayIndex, date.day);
      }
      await write(0, mode.code);
    } else {
      // off first, then back to the unused default 01.01.2015 (day/month
      // before the year – 1.1. is valid in any year)
      await write(0, mode.code);
      for (final (index, value) in [(1, 1), (2, 1), (3, 2015), (4, 1), (5, 1), (6, 2015)]) {
        await write(index, value);
      }
    }
    await Future.delayed(const Duration(milliseconds: 200));
    return ControllerHolidayEntry.fromRaw(slot, await _readRaw(ControllerHolidayEntry.address(slot, 0), 7));
  }

  /// Controller clock (PNU 64045–64049), or null if not readable.
  Future<DateTime?> readControllerClock() async {
    try {
      final c = await _readRaw(64044, 5);
      return DateTime(c[4], c[3], c[2], c[0], c[1]);
    } catch (_) {
      return null;
    }
  }

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
      for (final param in _sensorParameters)
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
      for (final param in _sensorParameters) {
        try {
          results[param.id] = await readParameter(param);
        } catch (err) {
          failureCount++;
          lastError = err;
          debugPrint('[Modbus] Failed reading sensor ${param.id}: $err');
        }
      }
    }

    // 1b. Application-specific extra sensors (optional)
    for (final param in extraSensors) {
      try {
        results[param.id] = await readParameter(param);
      } catch (err) {
        debugPrint('[Modbus] Extra sensor ${param.id} not available: $err');
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
