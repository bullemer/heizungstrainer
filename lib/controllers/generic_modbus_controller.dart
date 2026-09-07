import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';

/// Real hardware adapter for generic heating systems communicating via Modbus TCP.
///
/// Supports systems such as:
/// - Technische Alternative (UVR16x2 / C.M.I.)
/// - Siemens Synco 700 / OZW772
/// - Wolf Heizung (BM-2 / ISM7 Modbus)
/// - Luxtronik, Stiebel Eltron, Weishaupt, Keba, etc.
class GenericModbusController implements HeatingController {
  GenericModbusConfig _config;
  ModbusClientTcp? _client;
  bool _isConnected = false;
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
    } catch (e) {
      _isConnected = false;
      _client = null;
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

  bool _isDisconnectedRaw(int? raw) {
    if (raw == null) return true;
    return raw == 0x7FFF || raw == -32768 || raw == 0xFFFF || raw == 32767;
  }

  double? _convertRaw(int? raw) {
    if (raw == null || _isDisconnectedRaw(raw)) return null;
    return double.parse((raw * _config.multiplier).toStringAsFixed(2));
  }

  ModbusElementType get _elementType => _config.isHoldingRegister
      ? ModbusElementType.holdingRegister
      : ModbusElementType.inputRegister;

  Future<int?> _readSingleRegister(int address) async {
    if (_client == null || !_isConnected) return null;
    final reg = ModbusInt16Register(
      name: 'reg_$address',
      type: _elementType,
      address: address,
    );
    try {
      final res = await _client!.send(reg.getReadRequest()).timeout(_timeout);
      if (res == ModbusResponseCode.requestSucceed) {
        return reg.value?.toInt();
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

    final rawOutdoor = await _readSingleRegister(_config.outdoorRegister);
    final rawFlow = await _readSingleRegister(_config.flowRegister);
    final rawReturn = await _readSingleRegister(_config.returnRegister);
    final rawHotWater = await _readSingleRegister(_config.hotWaterRegister);

    int? rawRoom;
    if (_config.roomTargetRegister != null) {
      rawRoom = await _readSingleRegister(_config.roomTargetRegister!);
    }

    int? rawShift;
    if (_config.heatingCurveShiftRegister != null) {
      rawShift = await _readSingleRegister(_config.heatingCurveShiftRegister!);
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

    _telemetryStreamController.add(telemetry);
    return telemetry;
  }

  @override
  Future<void> setHeatingCurveShift(double shift) async {
    if (_config.heatingCurveShiftRegister == null) {
      throw const ModbusCommunicationException(
        message: 'Kein Register für Parallelverschiebung konfiguriert.',
      );
    }
    if (_client == null || !_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum Modbus-TCP-Regler.',
      );
    }

    final raw = (shift / _config.multiplier).round();
    final reg = ModbusInt16Register(
      name: 'shift_reg',
      type: ModbusElementType.holdingRegister,
      address: _config.heatingCurveShiftRegister!,
    );

    final res = await _client!.send(reg.getWriteRequest(raw)).timeout(_timeout);
    if (res != ModbusResponseCode.requestSucceed) {
      throw ModbusCommunicationException(
        message: 'Schreiben der Parallelverschiebung fehlgeschlagen (Code $res).',
      );
    }
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    if (_config.roomTargetRegister == null) {
      throw const ModbusCommunicationException(
        message: 'Kein Register für Raum-Sollwert konfiguriert.',
      );
    }
    if (_client == null || !_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum Modbus-TCP-Regler.',
      );
    }

    final raw = (temperature / _config.multiplier).round();
    final reg = ModbusInt16Register(
      name: 'room_reg',
      type: ModbusElementType.holdingRegister,
      address: _config.roomTargetRegister!,
    );

    final res = await _client!.send(reg.getWriteRequest(raw)).timeout(_timeout);
    if (res != ModbusResponseCode.requestSucceed) {
      throw ModbusCommunicationException(
        message: 'Schreiben der Raum-Soll-Temperatur fehlgeschlagen (Code $res).',
      );
    }
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
}
