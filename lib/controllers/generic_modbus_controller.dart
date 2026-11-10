import 'package:heizungstrainer/utils/number_format.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';

/// Real hardware adapter for generic heating systems communicating via Modbus TCP.
///
/// The register map comes from the user (or a preset such as Stiebel ISG or
/// Samson TROVIS). The provider polls [readTelemetry]; this class has no
/// timer of its own.
class GenericModbusController implements HeatingController {
  GenericModbusConfig _config;
  ModbusClientTcp? _client;
  bool _isConnected = false;
  DateTime? _lastPollTime;
  ControllerTelemetry? _cachedTelemetry;

  final StreamController<ControllerTelemetry> _telemetryStreamController =
      StreamController<ControllerTelemetry>.broadcast();

  static const Duration _timeout = Duration(seconds: 4);

  GenericModbusController({
    GenericModbusConfig? config,
    ModbusClientTcp? client,
  })  : _config = config ?? const GenericModbusConfig(),
        _client = client;

  GenericModbusConfig get config => _config;

  void updateConfig(GenericModbusConfig newConfig) {
    _config = newConfig;
  }

  @override
  String get id => 'generic_modbus';

  @override
  String get brandName => 'Generisch (Modbus TCP)';

  @override
  String get modelName => _config.presetName;

  @override
  ConnectionProtocol get protocol => ConnectionProtocol.modbusTcp;

  @override
  HeatingCapabilities get capabilities => HeatingCapabilities(
        supportsHeatingCurveShift: _config.heatingCurveShiftRegister != null,
        minShift: -15.0,
        maxShift: 15.0,
        supportsRoomTarget: _config.roomTargetRegister != null,
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

    final targetPort = port ?? _config.port;
    _client = ModbusClientTcp(
      host,
      serverPort: targetPort,
      unitId: _config.unitId,
      connectionMode: ModbusConnectionMode.autoConnectAndKeepConnected,
    );

    try {
      final connected = await _client!.connect();
      _isConnected = connected;
      if (!connected) {
        throw ModbusCommunicationException(
          message: 'Verbindung zum Modbus-TCP-Regler unter $host:$targetPort fehlgeschlagen.',
        );
      }

      // First read proves that the register map answers at all.
      await readTelemetry();
    } catch (e) {
      await disconnect();
      if (e is ModbusCommunicationException) rethrow;
      throw ModbusCommunicationException(
        message: 'Fehler beim Verbinden zu $host:$targetPort: $e',
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
  }

  bool _isDisconnectedRaw(num? raw) {
    if (raw == null) return false;
    return raw == 0x7FFF ||
        raw == -32768 ||
        raw == 0xFFFF ||
        raw == 32767 ||
        raw == 0x7FFFFFFF ||
        raw == -2147483648;
  }

  double? _convertRaw(num? raw) {
    if (raw == null || _isDisconnectedRaw(raw)) return null;
    return double.parse((raw * _config.multiplier).fixed(2));
  }

  ModbusElementType get _elementType => _config.isHoldingRegister
      ? ModbusElementType.holdingRegister
      : ModbusElementType.inputRegister;

  /// Sensors use the configured register type; setpoints ([holding]) are
  /// always holding registers, because that is where they are written.
  Future<num?> _readRegisterRaw(int address, {bool holding = false}) async {
    if (_client == null || !_isConnected) return null;
    final endianness = _config.wordOrder.toModbusEndianness;
    final type = holding ? ModbusElementType.holdingRegister : _elementType;
    final ModbusElement element;

    switch (_config.dataType) {
      case ModbusRegisterDataType.int16:
        element = ModbusInt16Register(
          name: 'reg_$address',
          type: type,
          address: address,
          endianness: endianness,
        );
        break;
      case ModbusRegisterDataType.uint16:
        element = ModbusUint16Register(
          name: 'reg_$address',
          type: type,
          address: address,
          endianness: endianness,
        );
        break;
      case ModbusRegisterDataType.int32:
        element = ModbusInt32Register(
          name: 'reg_$address',
          type: type,
          address: address,
          endianness: endianness,
        );
        break;
      case ModbusRegisterDataType.uint32:
        element = ModbusUint32Register(
          name: 'reg_$address',
          type: type,
          address: address,
          endianness: endianness,
        );
        break;
      case ModbusRegisterDataType.float32:
        element = ModbusFloatRegister(
          name: 'reg_$address',
          type: type,
          address: address,
          endianness: endianness,
        );
        break;
    }

    try {
      final res = await _client!.send(element.getReadRequest()).timeout(_timeout);
      if (res == ModbusResponseCode.requestSucceed) {
        return element.value as num?;
      }
    } catch (e) {
      debugPrint('[GenericModbus] Read reg $address error: $e');
    }
    return null;
  }

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    if (_client == null || !_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine aktive Verbindung zum Modbus-TCP-Regler.',
      );
    }

    // Rate-limiting throttle: if called too frequently (within 1.5s),
    // return cached telemetry to protect fragile gateways (e.g. Stiebel ISG).
    final now = DateTime.now();
    if (_lastPollTime != null &&
        now.difference(_lastPollTime!) < const Duration(milliseconds: 1500) &&
        _cachedTelemetry != null) {
      return _cachedTelemetry!;
    }
    _lastPollTime = now;

    final rawOutdoor = await _readRegisterRaw(_config.outdoorRegister);
    final rawFlow = await _readRegisterRaw(_config.flowRegister);
    final rawReturn = await _readRegisterRaw(_config.returnRegister);
    final rawHotWater = await _readRegisterRaw(_config.hotWaterRegister);

    num? rawRoom;
    if (_config.roomTargetRegister != null) {
      rawRoom = await _readRegisterRaw(_config.roomTargetRegister!, holding: true);
    }

    num? rawShift;
    if (_config.heatingCurveShiftRegister != null) {
      rawShift = await _readRegisterRaw(_config.heatingCurveShiftRegister!, holding: true);
    }

    if (rawOutdoor == null && rawFlow == null && rawReturn == null && rawHotWater == null) {
      throw const ModbusCommunicationException(
        message: 'Der Regler antwortet, liefert aber auf keinem der eingestellten Register einen Wert. '
            'Registeradressen, Registertyp und Unit-ID prüfen.',
      );
    }

    final outdoor = _convertRaw(rawOutdoor);
    final flow = _convertRaw(rawFlow);
    final ret = _convertRaw(rawReturn);
    final hw = _convertRaw(rawHotWater);
    final room = _convertRaw(rawRoom);
    final shift = _convertRaw(rawShift);

    final telemetry = ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoor,
      flowTemp: flow,
      returnTemp: ret,
      hotWaterTemp: hw,
      roomTarget: room,
      heatingCurveShift: shift,
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

  Future<void> _writeRegisterValue(int address, double value, String label) async {
    if (_client == null || !_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum Modbus-TCP-Regler.',
      );
    }

    final endianness = _config.wordOrder.toModbusEndianness;
    final ModbusElement element;
    final dynamic writeValue;

    switch (_config.dataType) {
      case ModbusRegisterDataType.int16:
        element = ModbusInt16Register(
          name: 'write_$address',
          type: ModbusElementType.holdingRegister,
          address: address,
          endianness: endianness,
        );
        writeValue = (value / _config.multiplier).round();
        break;
      case ModbusRegisterDataType.uint16:
        element = ModbusUint16Register(
          name: 'write_$address',
          type: ModbusElementType.holdingRegister,
          address: address,
          endianness: endianness,
        );
        writeValue = (value / _config.multiplier).round();
        break;
      case ModbusRegisterDataType.int32:
        element = ModbusInt32Register(
          name: 'write_$address',
          type: ModbusElementType.holdingRegister,
          address: address,
          endianness: endianness,
        );
        writeValue = (value / _config.multiplier).round();
        break;
      case ModbusRegisterDataType.uint32:
        element = ModbusUint32Register(
          name: 'write_$address',
          type: ModbusElementType.holdingRegister,
          address: address,
          endianness: endianness,
        );
        writeValue = (value / _config.multiplier).round();
        break;
      case ModbusRegisterDataType.float32:
        element = ModbusFloatRegister(
          name: 'write_$address',
          type: ModbusElementType.holdingRegister,
          address: address,
          endianness: endianness,
        );
        writeValue = value / _config.multiplier;
        break;
    }

    final res = await _client!.send(element.getWriteRequest(writeValue)).timeout(_timeout);
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
  Future<void> setHeatingCurveShift(double shift) async {
    if (_config.heatingCurveShiftRegister == null) {
      throw const ModbusCommunicationException(
        message: 'Kein Register für Parallelverschiebung konfiguriert.',
      );
    }
    await _writeRegisterValue(
      _config.heatingCurveShiftRegister!,
      shift,
      'Parallelverschiebung',
    );
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    if (_config.roomTargetRegister == null) {
      throw const ModbusCommunicationException(
        message: 'Kein Register für Raum-Sollwert konfiguriert.',
      );
    }
    await _writeRegisterValue(
      _config.roomTargetRegister!,
      temperature,
      'Raum-Solltemperatur',
    );
  }

  /// Attempts a quick connection and telemetry read to verify configuration.
  static Future<Map<String, dynamic>> testConnection(
    GenericModbusConfig config,
  ) async {
    final controller = GenericModbusController(config: config);
    try {
      await controller.connect(host: config.host, port: config.port);
      final telemetry = await controller.readTelemetry();
      await controller.disconnect();
      return {
        'success': true,
        'flow': telemetry.flowTemp,
        'return': telemetry.returnTemp,
        'outdoor': telemetry.outdoorTemp,
        'hotWater': telemetry.hotWaterTemp,
      };
    } catch (e) {
      await controller.disconnect();
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
