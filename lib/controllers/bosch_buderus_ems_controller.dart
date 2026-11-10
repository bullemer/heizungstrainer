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

/// Heating controller adapter for Bosch, Buderus and Junkers systems. Two
/// gateways, both NOT verified on hardware:
///
/// - EMS-ESP (emsesp.org) REST API: `GET /api/boiler` (curflowtemp, rettemp,
///   outdoortemp, DHW as `wwcurtemp` up to 3.6 or nested `dhw.curtemp` from
///   3.7) and `GET /api/thermostat` (per circuit `hc1.seltemp`,
///   `hc1.offsettemp` – the latter only on some thermostats). Writes are
///   `POST /api/thermostat {"cmd": …, "data": …, "id": circuit}` with a
///   Bearer token; from EMS-ESP 3.10 every call needs an API key.
/// - Bosch/Buderus KM200 / KM50 / KM100: AES-256-ECB (zero padding), base64
///   body, key from gateway + private password (see the config class).
///   Writes are POSTs of the encrypted `{"value": x}`. No heating-curve
///   offset is writable there.
///
/// The provider polls [readTelemetry]; this class has no timer of its own.
class BoschBuderusEmsController implements HeatingController {
  BoschBuderusEmsConfig _config;
  bool _isConnected = false;
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

  bool get _isKm200 => _config.gatewayType == BoschGatewayType.km200;

  @override
  HeatingCapabilities get capabilities => HeatingCapabilities(
        // KM200 exposes no writable heating-curve offset.
        supportsHeatingCurveShift: !_isKm200,
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
      await _probeGateway();
      _isConnected = true;
      final initial = await readTelemetry();
      _telemetryController.add(initial);
    } catch (e) {
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
    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = null;
    _isConnected = false;
  }

  /// Throws with a specific reason when the gateway cannot be used.
  Future<void> _probeGateway() async {
    if (_isKm200) {
      if (_config.getKm200KeyBytes() == null) {
        throw const ModbusCommunicationException(
          message: 'Für das KM200 fehlen Gateway-Passwort und privates Passwort.',
        );
      }
      // Throws when the gateway answers but the key does not fit.
      final res = await _httpGetKm200('/gateway/versionFirmware') ??
          await _httpGetKm200('/system/sensors/temperatures/outdoor_t1');
      if (res == null) {
        throw ModbusCommunicationException(
          message: 'Unter ${_config.baseUrl} antwortet kein KM200-Gateway.',
        );
      }
      return;
    }
    final res = await _httpGet('/api/system') ?? await _httpGet('/api/boiler');
    if (res == null) {
      throw ModbusCommunicationException(
        message: 'Unter ${_config.baseUrl} antwortet kein EMS-ESP.',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // KM200: AES-256-ECB, zero padding, base64
  // ──────────────────────────────────────────────────────────────────

  enc.Encrypter? _km200Cipher() {
    final keyBytes = _config.getKm200KeyBytes();
    if (keyBytes == null) return null;
    return enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.ecb, padding: null));
  }

  String? _decryptKm200(String base64Body) {
    try {
      final cipher = _km200Cipher();
      if (cipher == null) return null;
      final clean = base64Body.replaceAll(RegExp(r'\s+'), '');
      final bytes = cipher.decryptBytes(enc.Encrypted.fromBase64(clean));
      // Strip the padding (zero bytes; some firmware pads PKCS#7-style).
      var end = bytes.length;
      while (end > 0 && bytes[end - 1] <= 0x10) {
        end--;
      }
      return utf8.decode(bytes.sublist(0, end));
    } catch (e) {
      debugPrint('[KM200] Decrypt error: $e');
      return null;
    }
  }

  String? _encryptKm200(String jsonPayload) {
    try {
      final cipher = _km200Cipher();
      if (cipher == null) return null;
      final data = utf8.encode(jsonPayload);
      final padded = Uint8List((data.length + 15) ~/ 16 * 16)..setAll(0, data);
      return cipher.encryptBytes(padded).base64;
    } catch (e) {
      debugPrint('[KM200] Encrypt error: $e');
      return null;
    }
  }

  static const _km200UserAgent = 'TeleHeater/2.2.3';

  /// Decrypted JSON of a KM200 service; null when the service does not exist.
  Future<dynamic> _httpGetKm200(String endpoint) async {
    final uri = _config.getUri(endpoint);
    final client = _getClient();
    final req = await client.getUrl(uri).timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    req.headers.set(HttpHeaders.userAgentHeader, _km200UserAgent);
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
    dynamic json;
    try {
      json = decrypted == null ? null : jsonDecode(decrypted);
    } catch (_) {}
    if (json == null) {
      throw const ModbusCommunicationException(
        message: 'Das KM200 antwortet, aber die Antwort lässt sich nicht entschlüsseln – '
            'Gateway-Passwort und privates Passwort prüfen.',
      );
    }
    return json;
  }

  Future<bool> _httpWriteKm200(String endpoint, Map<String, dynamic> payload) async {
    final uri = _config.getUri(endpoint);
    final client = _getClient();
    final req = await client.postUrl(uri).timeout(
      Duration(seconds: _config.timeoutSeconds),
    );
    req.headers.set(HttpHeaders.userAgentHeader, _km200UserAgent);
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

  static const _tokenHint = 'EMS-ESP verlangt ein gültiges Zugriffstoken '
      '(ab Version 3.10 einen API-Schlüssel – zum Schreiben mit Schreibrecht).';

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
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      await resp.drain<void>();
      throw const ModbusCommunicationException(message: _tokenHint);
    }
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
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const ModbusCommunicationException(message: _tokenHint);
    }
    return isSuccess;
  }

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    if (_config.gatewayType == BoschGatewayType.km200) {
      return _readKm200Telemetry();
    }
    return _readEmsEspTelemetry();
  }

  /// First numeric value of the given KM200 services; a sensor that is not
  /// connected reports −3276.8.
  Future<double?> _km200Value(List<String> paths) async {
    for (final path in paths) {
      final json = await _httpGetKm200(path);
      final v = json is Map ? json['value'] : null;
      if (v is num && v > -3000) return v.toDouble();
    }
    return null;
  }

  Future<String?> _km200Text(String path) async {
    final json = await _httpGetKm200(path);
    final v = json is Map ? json['value'] : null;
    return v is String ? v : null;
  }

  Future<ControllerTelemetry> _readKm200Telemetry() async {
    final hc = '/heatingCircuits/${_config.circuit}';
    final outdoorTemp = await _km200Value(['/system/sensors/temperatures/outdoor_t1']);
    final flowTemp = await _km200Value([
      '$hc/actualSupplyTemperature',
      '/system/sensors/temperatures/supply_t1',
      '/heatSources/actualSupplyTemperature',
    ]);
    final returnTemp = await _km200Value([
      '/system/sensors/temperatures/return',
      '/heatSources/returnTemperature',
    ]);
    final hotWaterTemp = await _km200Value([
      '/dhwCircuits/dhw1/actualTemp',
      '/system/sensors/temperatures/hotWater_t2',
    ]);
    final roomTarget = await _km200Value(['$hc/currentRoomSetpoint']);

    if (outdoorTemp == null && flowTemp == null && returnTemp == null && hotWaterTemp == null) {
      throw const ModbusCommunicationException(
        message: 'Das KM200 liefert keinen der erwarteten Temperaturwerte.',
      );
    }

    return ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoorTemp,
      flowTemp: flowTemp,
      returnTemp: returnTemp,
      hotWaterTemp: hotWaterTemp,
      roomTarget: roomTarget,
      rawValues: {
        'km200.outdoor': ?outdoorTemp,
        'km200.flow': ?flowTemp,
        'km200.return': ?returnTemp,
        'km200.hotWater': ?hotWaterTemp,
        'km200.roomTarget': ?roomTarget,
      },
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
        // EMS-ESP <= 3.6: flat `wwcurtemp`; from 3.7: nested `dhw.curtemp`.
        final dhw = boilerData['dhw'];
        hotWaterTemp = _extractDouble(boilerData, ['wwcurtemp']) ??
            (dhw is Map<String, dynamic> ? _extractDouble(dhw, ['curtemp']) : null);

        boilerData.forEach((k, v) {
          if (v is num) rawValues['boiler.$k'] = v.toDouble();
        });
      }
    } on ModbusCommunicationException {
      rethrow;
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

        roomTarget = _extractDouble(circuitMap, ['seltemp']);

        // Only some thermostats have it; without it the shift stays "—".
        heatingCurveShift = _extractDouble(circuitMap, ['offsettemp']);

        circuitMap.forEach((k, v) {
          if (v is num) rawValues['thermostat.$circuitKey.$k'] = v.toDouble();
        });
      }
    } on ModbusCommunicationException {
      rethrow;
    } catch (e) {
      debugPrint('[BoschBuderusEmsController] Error reading thermostat: $e');
    }

    if (outdoorTemp == null && flowTemp == null && returnTemp == null && hotWaterTemp == null && roomTarget == null) {
      throw const ModbusCommunicationException(
        message: 'EMS-ESP liefert keinen der erwarteten Werte (curflowtemp, rettemp, outdoortemp, seltemp).',
      );
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

    if (_isKm200) {
      throw const ModbusCommunicationException(
        message: 'Das KM200 bietet keine schreibbare Parallelverschiebung. '
            'Stattdessen die Raum-Solltemperatur ändern.',
      );
    }

    final circuitNum = _circuitToNumber(_config.circuit);

    // Try standard EMS-ESP v3 endpoint
    var success = await _httpPost('/api/thermostat', {
      'cmd': 'offsettemp',
      'data': shift,
      'id': circuitNum,
    });

    // Same command in path form
    if (!success) {
      success = await _httpPost('/api/thermostat/${_config.circuit}/offsettemp', {
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

    if (_isKm200) {
      // Manual mode has its own setpoint; in the time programme the
      // temporary setpoint overrides until the next switching point.
      final hc = '/heatingCircuits/${_config.circuit}';
      final manual = (await _km200Text('$hc/operationMode'))?.toLowerCase() == 'manual';
      final success = await _httpWriteKm200(
        '$hc/${manual ? 'manualRoomSetpoint' : 'temporaryRoomSetpoint'}',
        {'value': temperature},
      );
      if (!success) {
        throw ModbusCommunicationException(
          message: 'KM200 Raum-Solltemperatur (${temperature.de(1)} °C) '
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
        message: 'EMS-ESP Raum-Solltemperatur (${temperature.de(1)} °C) '
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
        await controller._probeGateway();
        final telemetry = await controller.readTelemetry();
        return {
          'success': true,
          'message': 'KM200 erreicht, entschlüsselt und Werte gelesen.',
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
        'message': e is ModbusCommunicationException ? e.message : 'Verbindungstest fehlgeschlagen: $e',
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
