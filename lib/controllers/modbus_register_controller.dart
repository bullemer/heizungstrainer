import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/utils/number_format.dart';

/// What a register-map driver needs to know about the device: where the four
/// sensors and the two setpoints live and how the raw values are encoded.
class ModbusRegisterMap {
  final int port;
  final int unitId;
  final int outdoorRegister;
  final int flowRegister;
  final int returnRegister;
  final int hotWaterRegister;
  final int? roomTargetRegister;
  final int? heatingCurveShiftRegister;

  /// Raw → °C for the temperatures (0.1 = tenths of a degree).
  final double multiplier;

  /// Raw → K for the curve shift. NIBE stores whole steps, the others tenths.
  final double shiftMultiplier;

  /// Sensors are read as holding registers (FC03) instead of input registers
  /// (FC04). Setpoints are always holding registers.
  final bool sensorsAreHolding;
  final ModbusWordOrder wordOrder;
  final ModbusRegisterDataType dataType;

  /// Write with FC 0x10 even for one register (NIBE MODBUS 40 has no FC 0x06).
  final bool writeMultiple;

  const ModbusRegisterMap({
    required this.port,
    required this.unitId,
    required this.outdoorRegister,
    required this.flowRegister,
    required this.returnRegister,
    required this.hotWaterRegister,
    required this.roomTargetRegister,
    required this.heatingCurveShiftRegister,
    required this.multiplier,
    double? shiftMultiplier,
    required this.sensorsAreHolding,
    this.wordOrder = ModbusWordOrder.bigEndian,
    this.dataType = ModbusRegisterDataType.int16,
    this.writeMultiple = false,
  }) : shiftMultiplier = shiftMultiplier ?? multiplier;
}

/// Shared Modbus TCP driver for devices that expose plain temperature
/// registers (NIBE, Weishaupt heat pumps, user-defined maps).
///
/// Subclasses only supply the register map and the names used in messages.
/// The provider polls [readTelemetry]; this class has no timer of its own.
abstract class ModbusRegisterController implements HeatingController {
  ModbusClientTcp? _client;
  bool _isConnected = false;
  final StreamController<ControllerTelemetry> _telemetryStreamController =
      StreamController<ControllerTelemetry>.broadcast();

  DateTime? _lastPollTime;
  ControllerTelemetry? _cachedTelemetry;

  static const Duration _timeout = Duration(seconds: 4);

  ModbusRegisterController({ModbusClientTcp? client}) : _client = client;

  /// Register map of the current configuration.
  @protected
  ModbusRegisterMap get registerMap;

  /// Device name with its German dative article, e.g. "zur NIBE Wärmepumpe".
  @protected
  String get deviceDative;

  /// Device name as a sentence subject, e.g. "NIBE Wärmepumpe".
  @protected
  String get deviceName;

  /// Prefix for debug output.
  @protected
  String get logTag;

  /// Minimum time between two real reads; calls in between get the last
  /// telemetry. Null = every call reads.
  @protected
  Duration? get readThrottle => null;

  @protected
  double get minShift => -15.0;

  @protected
  double get maxShift => 15.0;

  @override
  ConnectionProtocol get protocol => ConnectionProtocol.modbusTcp;

  @override
  HeatingCapabilities get capabilities => HeatingCapabilities(
        supportsHeatingCurveShift: registerMap.heatingCurveShiftRegister != null,
        minShift: minShift,
        maxShift: maxShift,
        supportsRoomTarget: registerMap.roomTargetRegister != null,
        minRoomTarget: 5.0,
        maxRoomTarget: 30.0,
        supportsHotWater: true,
        supportsReturnTemp: true,
        supportsOutdoorTemp: true,
      );

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<ControllerTelemetry> get telemetryStream =>
      _telemetryStreamController.stream;

  @override
  Future<void> connect({
    required String host,
    int? port,
    Map<String, dynamic>? extraConfig,
  }) async {
    if (_client != null && _isConnected) {
      await disconnect();
    }

    final targetPort = port ?? registerMap.port;
    _client = ModbusClientTcp(
      host,
      serverPort: targetPort,
      unitId: registerMap.unitId,
      connectionMode: ModbusConnectionMode.autoConnectAndKeepConnected,
    );

    try {
      final connected = await _client!.connect();
      _isConnected = connected;
      if (!connected) {
        throw ModbusCommunicationException(
          message: 'Verbindung $deviceDative unter $host:$targetPort fehlgeschlagen.',
        );
      }
      // First read proves that the register map answers at all.
      await readTelemetry();
    } catch (e) {
      await disconnect();
      if (e is ModbusCommunicationException) rethrow;
      throw ModbusCommunicationException(
        message: 'Fehler beim Verbinden $deviceDative ($host:$targetPort): $e',
        underlyingError: e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _client?.disconnect();
    } catch (_) {}
    _client = null;
    _isConnected = false;
    _cachedTelemetry = null;
    _lastPollTime = null;
  }

  bool _isDisconnectedRaw(num? raw) {
    if (raw == null) return false;
    return raw == 0x7FFF ||
        raw == -32768 ||
        raw == 0xFFFF ||
        raw == 0x7FFFFFFF ||
        raw == -2147483648;
  }

  double? _convertRaw(num? raw, double multiplier) {
    if (raw == null || _isDisconnectedRaw(raw)) return null;
    return double.parse((raw * multiplier).fixed(2));
  }

  ModbusElement _element(String name, int address, ModbusElementType type) {
    final endianness = registerMap.wordOrder.toModbusEndianness;
    switch (registerMap.dataType) {
      case ModbusRegisterDataType.int16:
        return ModbusInt16Register(name: name, type: type, address: address, endianness: endianness);
      case ModbusRegisterDataType.uint16:
        return ModbusUint16Register(name: name, type: type, address: address, endianness: endianness);
      case ModbusRegisterDataType.int32:
        return ModbusInt32Register(name: name, type: type, address: address, endianness: endianness);
      case ModbusRegisterDataType.uint32:
        return ModbusUint32Register(name: name, type: type, address: address, endianness: endianness);
      case ModbusRegisterDataType.float32:
        return ModbusFloatRegister(name: name, type: type, address: address, endianness: endianness);
    }
  }

  /// Sensors use the configured register type; setpoints ([holding]) are
  /// always holding registers, because that is where they are written.
  Future<num?> _readRegisterRaw(int address, {bool holding = false}) async {
    if (_client == null || !_isConnected) return null;
    final element = _element(
      'reg_$address',
      address,
      holding || registerMap.sensorsAreHolding
          ? ModbusElementType.holdingRegister
          : ModbusElementType.inputRegister,
    );
    try {
      final res = await _client!.send(element.getReadRequest()).timeout(_timeout);
      if (res == ModbusResponseCode.requestSucceed) {
        return element.value as num?;
      }
    } catch (e) {
      debugPrint('[$logTag] Read reg $address error: $e');
    }
    return null;
  }

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    if (_client == null || !_isConnected) {
      throw ModbusCommunicationException(
        message: 'Keine aktive Verbindung $deviceDative.',
      );
    }

    // Fragile gateways (e.g. Stiebel ISG) must not be asked too often.
    final throttle = readThrottle;
    final now = DateTime.now();
    if (throttle != null &&
        _lastPollTime != null &&
        now.difference(_lastPollTime!) < throttle &&
        _cachedTelemetry != null) {
      return _cachedTelemetry!;
    }
    _lastPollTime = now;

    final map = registerMap;
    final rawOutdoor = await _readRegisterRaw(map.outdoorRegister);
    final rawFlow = await _readRegisterRaw(map.flowRegister);
    final rawReturn = await _readRegisterRaw(map.returnRegister);
    final rawHotWater = await _readRegisterRaw(map.hotWaterRegister);

    num? rawRoom;
    if (map.roomTargetRegister != null) {
      rawRoom = await _readRegisterRaw(map.roomTargetRegister!, holding: true);
    }

    num? rawShift;
    if (map.heatingCurveShiftRegister != null) {
      rawShift = await _readRegisterRaw(map.heatingCurveShiftRegister!, holding: true);
    }

    if (rawOutdoor == null && rawFlow == null && rawReturn == null && rawHotWater == null) {
      throw ModbusCommunicationException(
        message: '$deviceName antwortet, liefert aber auf keinem der eingestellten Register einen Wert. '
            'Registeradressen, Registertyp und Unit-ID prüfen.',
      );
    }

    final telemetry = ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: _convertRaw(rawOutdoor, map.multiplier),
      flowTemp: _convertRaw(rawFlow, map.multiplier),
      returnTemp: _convertRaw(rawReturn, map.multiplier),
      hotWaterTemp: _convertRaw(rawHotWater, map.multiplier),
      roomTarget: _convertRaw(rawRoom, map.multiplier),
      heatingCurveShift: _convertRaw(rawShift, map.shiftMultiplier),
      isOutdoorDisconnected: _isDisconnectedRaw(rawOutdoor),
      isFlowDisconnected: _isDisconnectedRaw(rawFlow),
      rawValues: {
        'outdoor': (rawOutdoor ?? 0).toDouble(),
        'flow': (rawFlow ?? 0).toDouble(),
        'return': (rawReturn ?? 0).toDouble(),
        'hotWater': (rawHotWater ?? 0).toDouble(),
        if (rawRoom != null) 'roomTarget': rawRoom.toDouble(),
        if (rawShift != null) 'shift': rawShift.toDouble(),
      },
    );

    _cachedTelemetry = telemetry;
    _telemetryStreamController.add(telemetry);
    return telemetry;
  }

  Future<void> _writeRegisterValue(
    int? address,
    double value,
    double multiplier, {
    required String label,
    required String missing,
  }) async {
    if (address == null) {
      throw ModbusCommunicationException(message: missing);
    }
    if (_client == null || !_isConnected) {
      throw ModbusCommunicationException(
        message: 'Keine Verbindung $deviceDative.',
      );
    }

    final map = registerMap;
    final element = _element('write_$address', address, ModbusElementType.holdingRegister);
    final scaled = value / multiplier;
    final ModbusRequest request;
    if (map.dataType == ModbusRegisterDataType.float32) {
      request = element.getWriteRequest(scaled);
    } else if (map.writeMultiple && map.dataType == ModbusRegisterDataType.int16) {
      request = element.getMultipleWriteRequest(
          (ByteData(2)..setInt16(0, scaled.round())).buffer.asUint8List());
    } else {
      request = element.getWriteRequest(scaled.round());
    }

    final res = await _client!.send(request).timeout(_timeout);
    if (res != ModbusResponseCode.requestSucceed) {
      throw ModbusCommunicationException(
        message: 'Schreiben von $label fehlgeschlagen (Code $res).',
      );
    }
    // The next read is the provider's read-back check; it must not be served
    // from the throttle cache with the pre-write value.
    _cachedTelemetry = null;
  }

  @override
  Future<void> setHeatingCurveShift(double shift) => _writeRegisterValue(
        registerMap.heatingCurveShiftRegister,
        shift,
        registerMap.shiftMultiplier,
        label: 'Parallelverschiebung',
        missing: 'Kein Register für Parallelverschiebung konfiguriert.',
      );

  @override
  Future<void> setRoomTarget(double temperature) => _writeRegisterValue(
        registerMap.roomTargetRegister,
        temperature,
        registerMap.multiplier,
        label: 'Raum-Solltemperatur',
        missing: 'Kein Register für Raum-Sollwert konfiguriert.',
      );

  /// Connects, reads once and disconnects; result map for the settings UI.
  @protected
  Future<Map<String, dynamic>> probe(String host, int port) async {
    try {
      await connect(host: host, port: port);
      final telemetry = await readTelemetry();
      await disconnect();
      return {
        'success': true,
        'flow': telemetry.flowTemp,
        'return': telemetry.returnTemp,
        'outdoor': telemetry.outdoorTemp,
        'hotWater': telemetry.hotWaterTemp,
      };
    } catch (e) {
      await disconnect();
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  void dispose() {
    disconnect();
    _telemetryStreamController.close();
  }
}
