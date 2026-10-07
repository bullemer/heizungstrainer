import 'package:heizungstrainer/utils/number_format.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/services/tls_policy.dart';

/// Representation of a discovered EMS-ESP / BBQKees gateway on the local network.
class DiscoveredEmsGateway {
  final String ip;
  final int port;
  final String version;
  final String model;

  const DiscoveredEmsGateway({
    required this.ip,
    required this.port,
    required this.version,
    required this.model,
  });
}

/// Heating controller adapter for Bosch, Buderus and Junkers systems
/// connected via an EMS-ESP gateway (Local REST API v2/v3) or official
/// Bosch / Buderus KM200 / MB LAN 2 / MX300 gateway (local AES-128-ECB).
///
/// Communicates over the local network via HTTP/HTTPS:
/// - EMS-ESP: `/api/system`, `/api/boiler`, `/api/thermostat`
/// - KM200: AES-128 encrypted `/gateway/versionFirmware`, `/system/...`, `/heatingCircuits/...`
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
  String get modelName => _config.gatewayType == BoschGatewayType.km200
      ? 'Buderus KM200 / MB LAN'
      : 'EMS-ESP Gateway (REST API)';

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
      ..badCertificateCallback = TlsPolicy.acceptSelfSignedOnLocalNetwork;
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
      // 1. Probe gateway
      final isOnline = await _probeGateway();
      if (!isOnline) {
        final gwName = _config.gatewayType == BoschGatewayType.km200
            ? 'Buderus KM200 Gateway'
            : 'EMS-ESP Gateway';
        throw ModbusCommunicationException(
          message: '$gwName unter ${_config.baseUrl} antwortet nicht.',
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
        message: 'Verbindung zu Bosch/Buderus fehlgeschlagen: $e',
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
    if (_config.gatewayType == BoschGatewayType.km200) {
      try {
        final res = await _httpGetKm200('/gateway/versionFirmware');
        if (res != null) return true;
      } catch (_) {}
      try {
        final res = await _httpGetKm200('/system/sensors/temperatures/outdoor_t1');
        if (res != null) return true;
      } catch (_) {}
      return false;
    }

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

  // ──────────────────────────────────────────────────────────────────
  // KM200 AES-128-ECB Helpers
  // ──────────────────────────────────────────────────────────────────

  String? _decryptKm200(String base64Body) {
    try {
      final keyBytes = _config.getKm200KeyBytes();
      if (keyBytes == null) return null;
      final key = enc.Key(keyBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb, padding: 'PKCS7'));
      final clean = base64Body.replaceAll(RegExp(r'\s+'), '');
      final encrypted = enc.Encrypted.fromBase64(clean);
      return encrypter.decrypt(encrypted);
    } catch (e) {
      debugPrint('[KM200] Decrypt error: $e');
      return null;
    }
  }

  String? _encryptKm200(String jsonPayload) {
    try {
      final keyBytes = _config.getKm200KeyBytes();
      if (keyBytes == null) return null;
      final key = enc.Key(keyBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.ecb, padding: 'PKCS7'));
      final encrypted = encrypter.encrypt(jsonPayload);
      return encrypted.base64;
    } catch (e) {
      debugPrint('[KM200] Encrypt error: $e');
      return null;
    }
  }

  Future<dynamic> _httpGetKm200(String endpoint) async {
    final uri = _config.getUri(endpoint);
    final client = _getClient();
    final req = await client.getUrl(uri).timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    req.headers.set(HttpHeaders.userAgentHeader, 'TeleHeater');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final resp = await req.close().timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return null;
    }

    final body = await resp.transform(utf8.decoder).join();
    if (body.trim().isEmpty) return null;
    final decrypted = _decryptKm200(body);
    if (decrypted == null || decrypted.trim().isEmpty) return null;
    return jsonDecode(decrypted);
  }

  Future<bool> _httpPutKm200(String endpoint, Map<String, dynamic> payload) async {
    final uri = _config.getUri(endpoint);
    final client = _getClient();
    final req = await client.putUrl(uri).timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    req.headers.set(HttpHeaders.userAgentHeader, 'TeleHeater');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

    final encrypted = _encryptKm200(jsonEncode(payload));
    if (encrypted == null) return false;
    req.write(encrypted);
    final resp = await req.close().timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    final success = resp.statusCode >= 200 && resp.statusCode < 300;
    await resp.drain<void>();
    return success;
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
    if (_config.gatewayType == BoschGatewayType.km200) {
      return _readKm200Telemetry();
    }
    return _readEmsEspTelemetry();
  }

  Future<ControllerTelemetry> _readKm200Telemetry() async {
    final rawValues = <String, double>{};
    double? outdoorTemp;
    double? flowTemp;
    double? returnTemp;
    double? hotWaterTemp;
    double? roomTarget;
    double? heatingCurveShift;

    try {
      final outdoorJson = await _httpGetKm200('/system/sensors/temperatures/outdoor_t1');
      if (outdoorJson is Map<String, dynamic> && outdoorJson['value'] is num) {
        outdoorTemp = (outdoorJson['value'] as num).toDouble();
        rawValues['km200.outdoor'] = outdoorTemp;
      }
    } catch (e) {
      debugPrint('[KM200] Error reading outdoor temp: $e');
    }

    try {
      final flowJson = await _httpGetKm200('/heatingCircuits/${_config.circuit}/actualSupplyTemperature');
      if (flowJson is Map<String, dynamic> && flowJson['value'] is num) {
        flowTemp = (flowJson['value'] as num).toDouble();
        rawValues['km200.flow'] = flowTemp;
      }
    } catch (e) {
      debugPrint('[KM200] Error reading flow temp: $e');
    }

    try {
      final returnJson = await _httpGetKm200('/system/sensors/temperatures/return');
      if (returnJson is Map<String, dynamic> && returnJson['value'] is num) {
        returnTemp = (returnJson['value'] as num).toDouble();
        rawValues['km200.return'] = returnTemp;
      }
    } catch (e) {
      debugPrint('[KM200] Error reading return temp: $e');
    }

    try {
      final hwJson = await _httpGetKm200('/dhwCircuits/dhw1/actualTemp');
      if (hwJson is Map<String, dynamic> && hwJson['value'] is num) {
        hotWaterTemp = (hwJson['value'] as num).toDouble();
        rawValues['km200.hotWater'] = hotWaterTemp;
      }
    } catch (e) {
      debugPrint('[KM200] Error reading hot water temp: $e');
    }

    try {
      final targetJson = await _httpGetKm200('/heatingCircuits/${_config.circuit}/temperatureRoomManual');
      if (targetJson is Map<String, dynamic> && targetJson['value'] is num) {
        roomTarget = (targetJson['value'] as num).toDouble();
        rawValues['km200.roomTarget'] = roomTarget;
      }
    } catch (e) {
      debugPrint('[KM200] Error reading room target: $e');
    }

    try {
      final shiftJson = await _httpGetKm200('/heatingCircuits/${_config.circuit}/roomTemperatureHeatingCurveOffset');
      if (shiftJson is Map<String, dynamic> && shiftJson['value'] is num) {
        heatingCurveShift = (shiftJson['value'] as num).toDouble();
        rawValues['km200.shift'] = heatingCurveShift;
      }
    } catch (e) {
      debugPrint('[KM200] Error reading heating curve offset: $e');
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

  Future<ControllerTelemetry> _readEmsEspTelemetry() async {
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
        message: 'Keine aktive Verbindung zum Bosch/Buderus Gateway.',
      );
    }

    if (_config.gatewayType == BoschGatewayType.km200) {
      final success = await _httpPutKm200(
        '/heatingCircuits/${_config.circuit}/roomTemperatureHeatingCurveOffset',
        {'value': shift},
      );
      if (!success) {
        throw ModbusCommunicationException(
          message: 'KM200 Parallelverschiebung (${shift > 0 ? "+$shift" : "$shift"} K) '
              'konnte nicht gesetzt werden.',
        );
      }
      return;
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
        message: 'Keine aktive Verbindung zum Bosch/Buderus Gateway.',
      );
    }

    if (_config.gatewayType == BoschGatewayType.km200) {
      final success = await _httpPutKm200(
        '/heatingCircuits/${_config.circuit}/temperatureRoomManual',
        {'value': temperature},
      );
      if (!success) {
        throw ModbusCommunicationException(
          message: 'KM200 Raum-Solltemperatur (${temperature.fixed(1)} °C) '
              'konnte nicht gesetzt werden.',
        );
      }
      return;
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
        message: 'EMS-ESP Raum-Solltemperatur (${temperature.fixed(1)} °C) '
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
      if (config.gatewayType == BoschGatewayType.km200) {
        final online = await controller._probeGateway();
        if (!online) {
          return {
            'success': false,
            'message': 'KM200 Gateway antwortet nicht oder AES-128 Schlüssel ist ungültig.',
          };
        }
        final telemetry = await controller.readTelemetry();
        return {
          'success': true,
          'message': 'Buderus KM200 Gateway (AES-128) erfolgreich autorisiert!',
          'version': 'KM200/MB LAN',
          'outdoorTemp': telemetry.outdoorTemp,
          'flowTemp': telemetry.flowTemp,
          'returnTemp': telemetry.returnTemp,
          'hotWaterTemp': telemetry.hotWaterTemp,
          'roomTarget': telemetry.roomTarget,
        };
      }

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

  /// Discovers local EMS-ESP / BBQKees gateways via mDNS hostnames or IP scan.
  static Future<List<DiscoveredEmsGateway>> discoverEmsGateways({
    List<String>? candidateHosts,
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final results = <DiscoveredEmsGateway>[];
    final hosts = candidateHosts ?? [
      'ems-esp.local',
      'bbqkees-gateway.local',
      'ems-esp',
      'bbqkees-gateway',
    ];

    for (final host in hosts) {
      try {
        final client = HttpClient()..connectionTimeout = timeout;
        final uri = Uri.parse('http://$host:80/api/system');
        final req = await client.getUrl(uri).timeout(timeout);
        final resp = await req.close().timeout(timeout);
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>?;
          final version = json?['version'] as String? ?? json?['app'] as String? ?? 'v3.x';
          final model = json?['model'] as String? ?? json?['name'] as String? ?? 'EMS-ESP';
          results.add(DiscoveredEmsGateway(
            ip: host,
            port: 80,
            version: version,
            model: model,
          ));
        } else {
          await resp.drain<void>();
        }
        client.close(force: true);
      } catch (_) {}
    }
    return results;
  }

  void dispose() {
    disconnect();
    _telemetryController.close();
  }
}
