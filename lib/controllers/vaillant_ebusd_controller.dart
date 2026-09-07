import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';

/// Heating controller adapter for Vaillant heating systems connected via
/// an eBUSd daemon / gateway over HTTP REST JSON API.
///
/// Supports reading telemetry from `/data` (or `/data?exact=false`) and
/// writing heating curve shift and room setpoints via eBUSd write endpoints.
class VaillantEbusdController implements HeatingController {
  VaillantEbusdConfig _config;
  bool _isConnected = false;
  Timer? _pollingTimer;

  final StreamController<ControllerTelemetry> _telemetryController =
      StreamController<ControllerTelemetry>.broadcast();

  HttpClient? _httpClient;

  VaillantEbusdController({
    VaillantEbusdConfig? config,
    HttpClient? httpClient,
  })  : _config = config ?? const VaillantEbusdConfig(),
        _httpClient = httpClient;

  VaillantEbusdConfig get config => _config;

  void updateConfig(VaillantEbusdConfig config) {
    _config = config;
  }

  @override
  String get id => 'vaillant_ebusd';

  @override
  String get brandName => 'Vaillant';

  @override
  String get modelName => 'eBUS / eBUSd Gateway';

  @override
  ConnectionProtocol get protocol => ConnectionProtocol.restApi;

  @override
  HeatingCapabilities get capabilities => const HeatingCapabilities(
        supportsHeatingCurveShift: true,
        minShift: -15.0,
        maxShift: 15.0,
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
      final isOnline = await _probeGateway();
      if (!isOnline) {
        throw ModbusCommunicationException(
          message: 'eBUSd Gateway unter ${_config.baseUrl} antwortet nicht.',
        );
      }

      _isConnected = true;

      final initial = await readTelemetry();
      _telemetryController.add(initial);

      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (!_isConnected) return;
        try {
          final t = await readTelemetry();
          _telemetryController.add(t);
        } catch (e) {
          debugPrint('[VaillantEbusdController] Periodic poll error: $e');
        }
      });
    } catch (e) {
      _isConnected = false;
      await disconnect();
      if (e is ModbusCommunicationException) rethrow;
      throw ModbusCommunicationException(
        message: 'Verbindung zu eBUSd fehlgeschlagen: $e',
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
      final res = await _httpGet('/data');
      if (res != null) return true;
    } catch (_) {}

    try {
      final circuit = _config.circuit.trim().isEmpty ? 'bai' : _config.circuit.trim();
      final res = await _httpGet('/data/$circuit');
      if (res != null) return true;
    } catch (_) {}

    return false;
  }

  /// Sends an HTTP GET request to the eBUSd gateway.
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

  /// Writes a value to an eBUSd parameter endpoint via HTTP GET with value query.
  Future<bool> _httpWrite(String circuit, String parameter, dynamic value) async {
    final encodedVal = Uri.encodeComponent(value.toString());
    final endpoint = '/data/$circuit/$parameter?value=$encodedVal';
    final uri = _config.getUri(endpoint);
    final client = _getClient();

    try {
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
      final isSuccess = resp.statusCode >= 200 && resp.statusCode < 300;
      await resp.drain<void>();
      return isSuccess;
    } catch (e) {
      debugPrint('[VaillantEbusdController] Write error to $endpoint: $e');
      return false;
    }
  }

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    final rawValues = <String, double>{};
    dynamic data;

    try {
      data = await _httpGet('/data');
    } catch (e) {
      debugPrint('[VaillantEbusdController] Error querying /data: $e');
    }

    if (data == null) {
      final circuit = _config.circuit.trim().isEmpty ? 'bai' : _config.circuit.trim();
      try {
        data = await _httpGet('/data/$circuit');
      } catch (e) {
        debugPrint('[VaillantEbusdController] Error querying /data/$circuit: $e');
      }
    }

    if (data == null) {
      throw const ModbusCommunicationException(
        message: 'Keine Daten vom eBUSd Gateway empfangen.',
      );
    }

    final outdoor = _extractValue(data, [
      'outdoorstempsensor',
      'outside_temp',
      'outdoortemp',
      'outsidetemp',
      'outdoor',
    ]);
    final flow = _extractValue(data, [
      'flowtemp',
      'flow_temp',
      'flowtemperature',
      'curflowtemp',
      'actualflowtemp',
    ]);
    final ret = _extractValue(data, [
      'returntemp',
      'return_temp',
      'returntemperature',
      'rettemp',
    ]);
    final hotWater = _extractValue(data, [
      'storagetemp',
      'warmwatertemp',
      'hwctemp',
      'dhwtemp',
      'storagetempbottom',
      'waterstoragetemp',
    ]);
    final room = _extractValue(data, [
      'hc1desiredroomtemp',
      'desiredroomtemp',
      'roomtemptarget',
      'targetroomtemp',
      'roomtarget',
      'roomtemp',
    ]);
    final shift = _extractValue(data, [
      'hc1parallelshift',
      'parallelshift',
      'heatingcurveshift',
      'curveoffset',
      'shift',
      'offset',
    ]);

    if (outdoor != null) rawValues['outdoor'] = outdoor;
    if (flow != null) rawValues['flow'] = flow;
    if (ret != null) rawValues['return'] = ret;
    if (hotWater != null) rawValues['hotWater'] = hotWater;
    if (room != null) rawValues['roomTarget'] = room;
    if (shift != null) rawValues['shift'] = shift;

    return ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoor,
      flowTemp: flow,
      returnTemp: ret,
      hotWaterTemp: hotWater,
      roomTarget: room,
      heatingCurveShift: shift,
      rawValues: rawValues,
    );
  }

  /// Intelligently traverses nested eBUSd JSON tree to locate sensor values.
  static double? _extractValue(dynamic data, List<String> targetKeys) {
    if (data == null) return null;

    if (data is Map<String, dynamic>) {
      // 1. Direct match at current depth
      for (final target in targetKeys) {
        for (final entry in data.entries) {
          if (entry.key.toLowerCase() == target) {
            final val = _resolveRawNumber(entry.value);
            if (val != null) return val;
          }
        }
      }

      // 2. Recursive exploration for child objects
      for (final entry in data.entries) {
        if (entry.value is Map || entry.value is List) {
          final res = _extractValue(entry.value, targetKeys);
          if (res != null) return res;
        }
      }
    } else if (data is List) {
      for (final item in data) {
        final res = _extractValue(item, targetKeys);
        if (res != null) return res;
      }
    }

    return null;
  }

  static double? _resolveRawNumber(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val.replaceAll(',', '.'));
    }
    if (val is Map<String, dynamic>) {
      if (val.containsKey('value')) {
        return _resolveRawNumber(val['value']);
      }
      if (val.containsKey('temp')) {
        return _resolveRawNumber(val['temp']);
      }
      if (val.containsKey('temp-sensor')) {
        return _resolveRawNumber(val['temp-sensor']);
      }
      for (final entry in val.entries) {
        final parsed = _resolveRawNumber(entry.value);
        if (parsed != null) return parsed;
      }
    }
    if (val is List && val.isNotEmpty) {
      for (final item in val) {
        final parsed = _resolveRawNumber(item);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  @override
  Future<void> setHeatingCurveShift(double shift) async {
    if (!_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine aktive Verbindung zum eBUSd Gateway.',
      );
    }

    final circuit = _config.circuit.trim().isEmpty ? '700' : _config.circuit.trim();

    // Try primary circuit target
    var success = await _httpWrite(circuit, 'Hc1ParallelShift', shift);
    if (!success) {
      success = await _httpWrite(circuit, 'ParallelShift', shift);
    }
    if (!success && circuit != 'bai') {
      success = await _httpWrite('bai', 'Hc1ParallelShift', shift);
    }

    if (!success) {
      throw ModbusCommunicationException(
        message: 'eBUSd Parallelverschiebung (${shift > 0 ? "+$shift" : "$shift"} K) '
            'konnte nicht übertragen werden.',
      );
    }
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    if (!_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine aktive Verbindung zum eBUSd Gateway.',
      );
    }

    final circuit = _config.circuit.trim().isEmpty ? '700' : _config.circuit.trim();

    var success = await _httpWrite(circuit, 'Hc1DesiredRoomTemp', temperature);
    if (!success) {
      success = await _httpWrite(circuit, 'DesiredRoomTemp', temperature);
    }
    if (!success && circuit != 'bai') {
      success = await _httpWrite('bai', 'Hc1DesiredRoomTemp', temperature);
    }

    if (!success) {
      throw ModbusCommunicationException(
        message: 'eBUSd Raum-Solltemperatur (${temperature.toStringAsFixed(1)} °C) '
            'konnte nicht gesetzt werden.',
      );
    }
  }

  /// Live connection diagnostic probe for settings UI.
  static Future<Map<String, dynamic>> testConnection(
    VaillantEbusdConfig config, {
    HttpClient? httpClient,
  }) async {
    final controller = VaillantEbusdController(config: config, httpClient: httpClient);
    try {
      final probeSuccess = await controller._probeGateway();
      if (!probeSuccess) {
        return {
          'success': false,
          'message': 'Keine Antwort vom eBUSd Gateway unter ${config.baseUrl}.',
        };
      }

      final telemetry = await controller.readTelemetry();

      return {
        'success': true,
        'message': 'eBUSd Gateway erfolgreich erreicht!',
        'outdoorTemp': telemetry.outdoorTemp,
        'flowTemp': telemetry.flowTemp,
        'returnTemp': telemetry.returnTemp,
        'hotWaterTemp': telemetry.hotWaterTemp,
        'roomTarget': telemetry.roomTarget,
        'heatingCurveShift': telemetry.heatingCurveShift,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'eBUSd Verbindungstest fehlgeschlagen: $e',
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
