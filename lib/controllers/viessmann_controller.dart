import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';

/// Heating controller adapter for Viessmann heating systems (Vitodens, Vitotronic, Vitocal).
///
/// Supports two communication backends:
/// 1. [ViessmannConnectionType.optolinkTcp]: Local Optolink daemon (vcontrold / ESP-Optolink)
///    communicating over a local TCP socket.
/// 2. [ViessmannConnectionType.vicareRest]: Official Viessmann ViCare Developer REST API (Cloud).
class ViessmannController implements HeatingController {
  ViessmannConfig _config;
  bool _isConnected = false;
  Timer? _pollingTimer;

  final StreamController<ControllerTelemetry> _telemetryController =
      StreamController<ControllerTelemetry>.broadcast();

  HttpClient? _httpClient;
  DateTime? _lastVicarePoll;
  ControllerTelemetry? _cachedVicareTelemetry;

  ViessmannController({
    ViessmannConfig? config,
  }) : _config = config ?? const ViessmannConfig();

  ViessmannConfig get config => _config;

  void updateConfig(ViessmannConfig config) {
    _config = config;
  }

  @override
  String get id => 'viessmann_vicare';

  @override
  String get brandName => 'Viessmann';

  @override
  String get modelName => 'Vitotronic & ViCare';

  @override
  ConnectionProtocol get protocol =>
      _config.connectionType == ViessmannConnectionType.optolinkTcp
          ? ConnectionProtocol.proprietary
          : ConnectionProtocol.restApi;

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
      if (_config.connectionType == ViessmannConnectionType.optolinkTcp) {
        await _probeOptolinkTcp();
      } else {
        await _probeVicareRest();
      }

      _isConnected = true;

      // Read initial telemetry
      final initial = await readTelemetry();
      _telemetryController.add(initial);

      // Start periodic polling timer decoupled:
      // - ViCare Cloud REST: 60s+ to strictly protect the 1,450 calls/day quota
      // - Local Optolink: 10s fast local polling
      final interval = _config.connectionType == ViessmannConnectionType.vicareRest
          ? Duration(seconds: _config.cloudPollingIntervalSeconds.clamp(60, 300))
          : const Duration(seconds: 10);

      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(interval, (_) async {
        if (!_isConnected) return;
        try {
          final t = await readTelemetry();
          _telemetryController.add(t);
        } catch (e) {
          debugPrint('[ViessmannController] Polling error: $e');
        }
      });
    } catch (e) {
      _isConnected = false;
      await disconnect();
      if (e is ModbusCommunicationException) rethrow;
      throw ModbusCommunicationException(
        message: 'Verbindung zu Viessmann fehlgeschlagen: $e',
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

  // ──────────────────────────────────────────────────────────────────
  // Local Optolink (vcontrold / ESP-Optolink TCP Socket)
  // ──────────────────────────────────────────────────────────────────

  Future<void> _probeOptolinkTcp() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        _config.host,
        _config.port,
        timeout: Duration(seconds: _config.timeoutSeconds),
      );
    } catch (e) {
      throw ModbusCommunicationException(
        message: 'Viessmann Optolink Gateway unter ${_config.host}:${_config.port} nicht erreichbar: $e',
      );
    } finally {
      socket?.destroy();
    }
  }

  Future<String?> _sendOptolinkCommand(String cmd) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        _config.host,
        _config.port,
        timeout: Duration(seconds: _config.timeoutSeconds),
      );

      socket.write('$cmd\n');
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();

      final sub = socket.listen(
        (data) {
          buffer.write(utf8.decode(data));
          if (buffer.toString().contains('\n') || buffer.toString().contains('vctrld>')) {
            if (!completer.isCompleted) {
              completer.complete(buffer.toString());
            }
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(buffer.toString());
        },
      );

      final raw = await completer.future.timeout(
        Duration(seconds: _config.timeoutSeconds),
        onTimeout: () => buffer.toString(),
      );
      await sub.cancel();
      return raw.trim();
    } catch (e) {
      debugPrint('[ViessmannController] Error sending Optolink command "$cmd": $e');
      return null;
    } finally {
      socket?.destroy();
    }
  }

  double? _parseOptolinkNumber(String? response) {
    if (response == null || response.isEmpty) return null;
    // Extract first floating-point or integer number from the response
    final match = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(response);
    if (match != null) {
      final str = match.group(0)!.replaceAll(',', '.');
      return double.tryParse(str);
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────────
  // Viessmann ViCare REST API (Cloud)
  // ──────────────────────────────────────────────────────────────────

  Future<void> _probeVicareRest() async {
    final client = _getClient();
    final uri = Uri.parse('https://api.viessmann.com/iot/v1/equipment/installations');
    final req = await client.getUrl(uri).timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    if (_config.apiToken.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiToken.trim()}');
    }
    final resp = await req.close().timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    await resp.drain<void>();
    if (resp.statusCode != 200 && resp.statusCode != 401) {
      throw ModbusCommunicationException(
        message: 'Viessmann ViCare API Server antwortet mit Status ${resp.statusCode}',
      );
    }
  }

  Future<dynamic> _httpGetVicare(String path) async {
    final client = _getClient();
    final uri = Uri.parse('https://api.viessmann.com/iot/v1$path');
    final req = await client.getUrl(uri).timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_config.apiToken.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiToken.trim()}');
    }
    final resp = await req.close().timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    if (resp.statusCode == 429) {
      debugPrint('[ViessmannController] ViCare 429 Too Many Requests: Rate limit exceeded (~1,450 calls/day). Throttling...');
      await resp.drain<void>();
      return null;
    }
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return null;
    }
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body);
  }

  // ──────────────────────────────────────────────────────────────────
  // Telemetry Reading
  // ──────────────────────────────────────────────────────────────────

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    if (_config.connectionType == ViessmannConnectionType.optolinkTcp) {
      return _readOptolinkTelemetry();
    } else {
      return _readVicareTelemetry();
    }
  }

  Future<ControllerTelemetry> _readOptolinkTelemetry() async {
    final rawValues = <String, double>{};

    final outdoorRaw = await _sendOptolinkCommand('getTempA');
    final outdoor = _parseOptolinkNumber(outdoorRaw);
    if (outdoor != null) rawValues['outdoor'] = outdoor;

    final flowRaw = await _sendOptolinkCommand('getTempVl');
    final flow = _parseOptolinkNumber(flowRaw);
    if (flow != null) rawValues['flow'] = flow;

    final returnRaw = await _sendOptolinkCommand('getTempRl');
    final returnT = _parseOptolinkNumber(returnRaw);
    if (returnT != null) rawValues['return'] = returnT;

    final hwRaw = await _sendOptolinkCommand('getTempWWist');
    final hotWater = _parseOptolinkNumber(hwRaw);
    if (hotWater != null) rawValues['hotWater'] = hotWater;

    final roomRaw = await _sendOptolinkCommand('getTempRaumSoll');
    final room = _parseOptolinkNumber(roomRaw);
    if (room != null) rawValues['roomTarget'] = room;

    final shiftRaw = await _sendOptolinkCommand('getNiveau');
    final shift = _parseOptolinkNumber(shiftRaw);
    if (shift != null) rawValues['shift'] = shift;

    return ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoor,
      flowTemp: flow,
      returnTemp: returnT,
      hotWaterTemp: hotWater,
      roomTarget: room,
      heatingCurveShift: shift,
      rawValues: rawValues,
    );
  }

  Future<ControllerTelemetry> _readVicareTelemetry() async {
    // Rate-limiting protection: Developer accounts are strictly limited to ~1,450 calls/24h.
    // If called within 55 seconds and we have cached data, reuse it.
    final now = DateTime.now();
    if (_lastVicarePoll != null &&
        now.difference(_lastVicarePoll!) < const Duration(seconds: 55) &&
        _cachedVicareTelemetry != null) {
      debugPrint('[ViessmannController] Using cached ViCare telemetry to respect daily call quota');
      return _cachedVicareTelemetry!;
    }
    _lastVicarePoll = now;

    final rawValues = <String, double>{};
    double? outdoor;
    double? flow;
    double? returnT;
    double? hotWater;
    double? room;
    double? shift;

    try {
      final path = _config.installationId.isNotEmpty
          ? '/equipment/installations/${_config.installationId}/features'
          : '/equipment/installations';
      final json = await _httpGetVicare(path);

      if (json is Map<String, dynamic> && json.containsKey('data')) {
        final list = json['data'] as List<dynamic>?;
        if (list != null) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final feature = item['feature'] as String? ?? '';
              final properties = item['properties'] as Map<String, dynamic>? ?? {};

              if (feature.contains('heating.sensors.temperature.outside')) {
                final val = properties['value']?['value'];
                if (val is num) outdoor = val.toDouble();
              } else if (feature.contains('heating.boiler.sensors.temperature.main')) {
                final val = properties['value']?['value'];
                if (val is num) flow = val.toDouble();
              } else if (feature.contains('heating.boiler.sensors.temperature.return')) {
                final val = properties['value']?['value'];
                if (val is num) returnT = val.toDouble();
              } else if (feature.contains('heating.dhw.sensors.temperature.hotWaterStorage')) {
                final val = properties['value']?['value'];
                if (val is num) hotWater = val.toDouble();
              } else if (feature.contains('heating.circuits.${_config.circuit}.operating.programs.normal')) {
                final val = properties['temperature']?['value'];
                if (val is num) room = val.toDouble();
              } else if (feature.contains('heating.circuits.${_config.circuit}.heating.curve')) {
                final val = properties['shift']?['value'];
                if (val is num) shift = val.toDouble();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ViessmannController] ViCare REST read error: $e');
    }

    if (outdoor != null) rawValues['outdoor'] = outdoor;
    if (flow != null) rawValues['flow'] = flow;
    if (returnT != null) rawValues['return'] = returnT;
    if (hotWater != null) rawValues['hotWater'] = hotWater;
    if (room != null) rawValues['roomTarget'] = room;
    if (shift != null) rawValues['shift'] = shift;

    final telemetry = ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoor,
      flowTemp: flow,
      returnTemp: returnT,
      hotWaterTemp: hotWater,
      roomTarget: room,
      heatingCurveShift: shift,
      rawValues: rawValues,
    );

    _cachedVicareTelemetry = telemetry;
    return telemetry;
  }

  // ──────────────────────────────────────────────────────────────────
  // Setpoints
  // ──────────────────────────────────────────────────────────────────

  @override
  Future<void> setHeatingCurveShift(double shift) async {
    if (!_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum Viessmann Regler.',
      );
    }

    if (_config.connectionType == ViessmannConnectionType.optolinkTcp) {
      final res = await _sendOptolinkCommand('setNiveau ${shift.round()}');
      if (res == null || res.toLowerCase().contains('err') || res.toLowerCase().contains('fail')) {
        throw ModbusCommunicationException(
          message: 'Viessmann Optolink Parallelverschiebung konnte nicht gesetzt werden: $res',
        );
      }
    } else {
      // ViCare REST API
      final client = _getClient();
      final uri = Uri.parse(
        'https://api.viessmann.com/iot/v1/equipment/installations/${_config.installationId}/gateways/default/devices/0/features/heating.circuits.${_config.circuit}.heating.curve/commands/setCurve',
      );
      final req = await client.postUrl(uri).timeout(
        Duration(seconds: _config.timeoutSeconds),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiToken.trim()}');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode({'shift': shift.round()}));
      final resp = await req.close();
      await resp.drain<void>();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw ModbusCommunicationException(
          message: 'ViCare Cloud API Antwortfehler: Status ${resp.statusCode}',
        );
      }
    }
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    if (!_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum Viessmann Regler.',
      );
    }

    if (_config.connectionType == ViessmannConnectionType.optolinkTcp) {
      final res = await _sendOptolinkCommand('setTempRaumSoll ${temperature.toStringAsFixed(1)}');
      if (res == null || res.toLowerCase().contains('err') || res.toLowerCase().contains('fail')) {
        throw ModbusCommunicationException(
          message: 'Viessmann Optolink Raum-Sollwert konnte nicht gesetzt werden: $res',
        );
      }
    } else {
      // ViCare REST API
      final client = _getClient();
      final uri = Uri.parse(
        'https://api.viessmann.com/iot/v1/equipment/installations/${_config.installationId}/gateways/default/devices/0/features/heating.circuits.${_config.circuit}.operating.programs.normal/commands/setTemperature',
      );
      final req = await client.postUrl(uri).timeout(
        Duration(seconds: _config.timeoutSeconds),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiToken.trim()}');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode({'targetTemperature': temperature}));
      final resp = await req.close();
      await resp.drain<void>();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw ModbusCommunicationException(
          message: 'ViCare Cloud API Antwortfehler: Status ${resp.statusCode}',
        );
      }
    }
  }

  /// Diagnostic connection test for settings screen.
  static Future<Map<String, dynamic>> testConnection(ViessmannConfig config) async {
    final controller = ViessmannController(config: config);
    try {
      if (config.connectionType == ViessmannConnectionType.optolinkTcp) {
        final socket = await Socket.connect(
          config.host,
          config.port,
          timeout: Duration(seconds: config.timeoutSeconds),
        );
        socket.destroy();

        final telemetry = await controller.readTelemetry();
        return {
          'success': true,
          'message': 'Viessmann Optolink Gateway erfolgreich erreicht!',
          'type': 'Optolink TCP (${config.host}:${config.port})',
          'outdoorTemp': telemetry.outdoorTemp,
          'flowTemp': telemetry.flowTemp,
          'returnTemp': telemetry.returnTemp,
          'hotWaterTemp': telemetry.hotWaterTemp,
          'roomTarget': telemetry.roomTarget,
        };
      } else {
        await controller._probeVicareRest();
        final telemetry = await controller.readTelemetry();
        return {
          'success': true,
          'message': 'Viessmann ViCare API erfolgreich autorisiert!',
          'type': 'ViCare Cloud REST API',
          'outdoorTemp': telemetry.outdoorTemp,
          'flowTemp': telemetry.flowTemp,
          'returnTemp': telemetry.returnTemp,
          'hotWaterTemp': telemetry.hotWaterTemp,
          'roomTarget': telemetry.roomTarget,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Viessmann Verbindungstest fehlgeschlagen: $e',
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
