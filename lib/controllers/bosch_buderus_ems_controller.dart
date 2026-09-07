import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';

/// Heating controller adapter for Bosch, Buderus and Junkers systems
/// connected via an EMS-ESP gateway (Local REST API v2/v3).
///
/// Communicates over the local network via HTTP/HTTPS JSON endpoints:
/// - `/api/system` for gateway status, firmware version, and device discovery
/// - `/api/boiler` for flow temp, return temp, outdoor temp, and hot water temp
/// - `/api/thermostat` for heating circuits (hc1..hc4), room target, and curve shift
class BoschBuderusEmsController implements HeatingController {
  BoschBuderusEmsConfig _config;
  bool _isConnected = false;
  Timer? _pollingTimer;

  final StreamController<ControllerTelemetry> _telemetryController =
      StreamController<ControllerTelemetry>.broadcast();

  HttpClient? _httpClient;

  BoschBuderusEmsController({
    BoschBuderusEmsConfig? config,
  }) : _config = config ?? const BoschBuderusEmsConfig();

  BoschBuderusEmsConfig get config => _config;

  void updateConfig(BoschBuderusEmsConfig config) {
    _config = config;
  }

  @override
  String get id => 'bosch_buderus_ems';

  @override
  String get brandName => 'Bosch / Buderus';

  @override
  String get modelName => 'EMS-ESP Gateway (REST API)';

  @override
  ConnectionProtocol get protocol => ConnectionProtocol.restApi;

  @override
  HeatingCapabilities get capabilities => const HeatingCapabilities(
        supportsHeatingCurveShift: true,
        minShift: -10.0,
        maxShift: 10.0,
        supportsRoomTarget: true,
        minRoomTarget: 5.0,
        maxRoomTarget: 30.0,
        supportsHotWater: true,
        supportsReturnTemp: true,
        supportsOutdoorTemp: true,
      );

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<ControllerTelemetry> get telemetryStream => _telemetryController.stream;

  HttpClient _getClient() {
    return _httpClient ??= HttpClient()
      ..connectionTimeout = Duration(seconds: _config.timeoutSeconds)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }

  @override
  Future<void> connect({
    required String host,
    int? port,
    Map<String, dynamic>? extraConfig,
  }) async {
    if (_isConnected) {
      await disconnect();
    }

    _config = _config.copyWith(
      host: host,
      port: port ?? _config.port,
    );

    try {
      // 1. Probe gateway via /api/system or /api/boiler
      final isOnline = await _probeGateway();
      if (!isOnline) {
        throw ModbusCommunicationException(
          message: 'EMS-ESP Gateway unter ${_config.baseUrl} antwortet nicht.',
        );
      }

      _isConnected = true;

      // 2. Read initial telemetry
      final initial = await readTelemetry();
      _telemetryController.add(initial);

      // 3. Start telemetry stream (polling every 10s)
      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (!_isConnected) return;
        try {
          final t = await readTelemetry();
          _telemetryController.add(t);
        } catch (e) {
          debugPrint('[BoschBuderusEmsController] Periodic poll error: $e');
        }
      });
    } catch (e) {
      _isConnected = false;
      await disconnect();
      if (e is ModbusCommunicationException) rethrow;
      throw ModbusCommunicationException(
        message: 'Verbindung zu EMS-ESP fehlgeschlagen: $e',
        underlyingError: e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = null;
    _isConnected = false;
  }

  Future<bool> _probeGateway() async {
    try {
      final res = await _httpGet('/api/system');
      if (res != null) return true;
    } catch (_) {}

    try {
      final res = await _httpGet('/api/boiler');
      if (res != null) return true;
    } catch (_) {}

    return false;
  }

  /// Sends an HTTP GET request with timeout and authentication.
  Future<dynamic> _httpGet(String endpoint) async {
    final uri = _config.getUri(endpoint);
    final client = _getClient();

    final req = await client.getUrl(uri).timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_config.apiToken.trim().isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiToken.trim()}');
    }

    final resp = await req.close().timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return null;
    }

    final body = await resp.transform(utf8.decoder).join();
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  /// Sends an HTTP POST request with timeout, JSON body and authentication.
  Future<bool> _httpPost(String endpoint, Map<String, dynamic> payload) async {
    final uri = _config.getUri(endpoint);
    final client = _getClient();

    final req = await client.postUrl(uri).timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    if (_config.apiToken.trim().isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiToken.trim()}');
    }

    req.write(jsonEncode(payload));
    final resp = await req.close().timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    final isSuccess = resp.statusCode >= 200 && resp.statusCode < 300;
    await resp.drain<void>();
    return isSuccess;
  }

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    final rawValues = <String, double>{};
    double? outdoorTemp;
    double? flowTemp;
    double? returnTemp;
    double? hotWaterTemp;
    double? roomTarget;
    double? heatingCurveShift;

    // 1. Fetch Boiler data
    try {
      final boilerData = await _httpGet('/api/boiler');
      if (boilerData is Map<String, dynamic>) {
        flowTemp = _extractDouble(boilerData, [
          'curflowtemp',
          'curFlowTemp',
          'flowtemp',
          'actualflowtemp',
          'boilertemp',
          'boilerTemp',
        ]);
        returnTemp = _extractDouble(boilerData, [
          'rettemp',
          'returnTemp',
          'retflowtemp',
          'retFlowTemp',
          'return_temp',
        ]);
        outdoorTemp = _extractDouble(boilerData, [
          'outdoortemp',
          'outdoorTemp',
          'outdoor_temp',
        ]);
        hotWaterTemp = _extractDouble(boilerData, [
          'wwcurtemp',
          'wwCurTemp',
          'wwtemp',
          'dhwtemp',
          'dhwCurTemp',
          'curwwtemp',
        ]);

        boilerData.forEach((k, v) {
          if (v is num) rawValues['boiler.$k'] = v.toDouble();
        });
      }
    } catch (e) {
      debugPrint('[BoschBuderusEmsController] Error reading boiler: $e');
    }

    // 2. Fetch Thermostat data
    try {
      final thermostatData = await _httpGet('/api/thermostat');
      if (thermostatData is Map<String, dynamic>) {
        final circuitKey = _config.circuit.toLowerCase();
        Map<String, dynamic> circuitMap = thermostatData;

        if (thermostatData[circuitKey] is Map<String, dynamic>) {
          circuitMap = thermostatData[circuitKey] as Map<String, dynamic>;
        }

        roomTarget = _extractDouble(circuitMap, [
          'seltemp',
          'targettemp',
          'setpoint',
          'roomtarget',
          'heattemp',
        ]) ?? _extractDouble(thermostatData, ['seltemp', 'targettemp']);

        heatingCurveShift = _extractDouble(circuitMap, [
          'offset',
          'curveoffset',
          'shift',
          'parshift',
          'heatingcurveshift',
        ]) ?? _extractDouble(thermostatData, ['offset', 'curveoffset']);

        circuitMap.forEach((k, v) {
          if (v is num) rawValues['thermostat.$circuitKey.$k'] = v.toDouble();
        });
      }
    } catch (e) {
      debugPrint('[BoschBuderusEmsController] Error reading thermostat: $e');
    }

    return ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoorTemp,
      flowTemp: flowTemp,
      returnTemp: returnTemp,
      hotWaterTemp: hotWaterTemp,
      roomTarget: roomTarget,
      heatingCurveShift: heatingCurveShift,
      rawValues: rawValues,
    );
  }

  static double? _extractDouble(Map<String, dynamic> map, List<String> candidateKeys) {
    for (final key in candidateKeys) {
      // Check case-insensitively
      for (final entry in map.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase()) {
          final val = entry.value;
          if (val is num) return val.toDouble();
          if (val is String) {
            final parsed = double.tryParse(val.replaceAll(',', '.'));
            if (parsed != null) return parsed;
          }
        }
      }
    }
    return null;
  }

  @override
  Future<void> setHeatingCurveShift(double shift) async {
    if (!_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine aktive Verbindung zum EMS-ESP Gateway.',
      );
    }

    final circuitNum = _circuitToNumber(_config.circuit);

    // Try standard EMS-ESP v3 endpoint
    var success = await _httpPost('/api/thermostat', {
      'cmd': 'offset',
      'data': shift,
      'id': circuitNum,
    });

    // Fallback to direct circuit entity endpoint
    if (!success) {
      success = await _httpPost('/api/thermostat/${_config.circuit}/offset', {
        'value': shift,
      });
    }

    if (!success) {
      throw ModbusCommunicationException(
        message: 'EMS-ESP Parallelverschiebung (${shift > 0 ? "+$shift" : "$shift"} K) '
            'konnte nicht übertragen werden.',
      );
    }
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    if (!_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine aktive Verbindung zum EMS-ESP Gateway.',
      );
    }

    final circuitNum = _circuitToNumber(_config.circuit);

    // Try standard EMS-ESP v3 endpoint
    var success = await _httpPost('/api/thermostat', {
      'cmd': 'seltemp',
      'data': temperature,
      'id': circuitNum,
    });

    // Fallback to direct circuit entity endpoint
    if (!success) {
      success = await _httpPost('/api/thermostat/${_config.circuit}/seltemp', {
        'value': temperature,
      });
    }

    if (!success) {
      throw ModbusCommunicationException(
        message: 'EMS-ESP Raum-Solltemperatur (${temperature.toStringAsFixed(1)} °C) '
            'konnte nicht gesetzt werden.',
      );
    }
  }

  static int _circuitToNumber(String circuit) {
    final lower = circuit.toLowerCase();
    if (lower.startsWith('hc')) {
      final numStr = lower.substring(2);
      return int.tryParse(numStr) ?? 1;
    }
    return 1;
  }

  /// Live diagnostic probe for settings screen.
  static Future<Map<String, dynamic>> testConnection(
    BoschBuderusEmsConfig config,
  ) async {
    final controller = BoschBuderusEmsController(config: config);
    try {
      final client = controller._getClient();
      final sysUri = config.getUri('/api/system');
      final req = await client.getUrl(sysUri).timeout(
        Duration(seconds: config.timeoutSeconds),
      );
      if (config.apiToken.trim().isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.apiToken.trim()}');
      }
      final resp = await req.close().timeout(Duration(seconds: config.timeoutSeconds));

      String? version;
      String? uptime;
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>?;
        version = json?['version'] as String? ?? json?['app'] as String?;
        uptime = json?['uptime'] as String?;
      } else {
        await resp.drain<void>();
      }

      // Read sample telemetry
      final telemetry = await controller.readTelemetry();

      return {
        'success': true,
        'message': 'EMS-ESP Gateway erfolgreich erreicht!',
        'version': version ?? 'v3.x',
        'uptime': uptime,
        'outdoorTemp': telemetry.outdoorTemp,
        'flowTemp': telemetry.flowTemp,
        'returnTemp': telemetry.returnTemp,
        'hotWaterTemp': telemetry.hotWaterTemp,
        'roomTarget': telemetry.roomTarget,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Verbindungstest fehlgeschlagen: $e',
      };
    } finally {
      controller.disconnect();
    }
  }

  void dispose() {
    disconnect();
    _telemetryController.close();
  }
}
