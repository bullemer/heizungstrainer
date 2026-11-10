import 'package:heizungstrainer/utils/number_format.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';
import 'package:heizungstrainer/services/tls_policy.dart';

/// Heating controller adapter for Vaillant systems behind an ebusd daemon
/// (github.com/john30/ebusd). NOT verified on hardware.
///
/// Reading uses ebusd's HTTP JSON port (off by default: ebusd must run with
/// `--httpport`). `GET /data` lists the known messages as
/// `{circuit: {messages: {Name: {name, passive, write, lastup, zz, fields:
/// {field: {value}}}}}, global: {...}}`; single values are fetched with
/// `GET /data/CIRCUIT/NAME?maxage=…`, which makes ebusd read the bus when
/// its cached value is older.
///
/// ebusd's HTTP port is read-only (anything but GET → 405). Writing goes
/// through the TCP command port (default 8888): `write -c CIRCUIT NAME VALUE`
/// answers `done` or `ERR: …`.
///
/// Message names follow the ebusd Vaillant configuration: boiler circuit
/// `bai` (FlowTemp, ReturnTemp, OutdoorstempSensor, StorageTemp/HwcTemp) and
/// the regulator circuit from the config – `700` / `ctlv2` (Z1DayTemp) or
/// `470` (Hc1DayTemp). These regulators have no parallel-shift message, so
/// the curve shift is not supported.
///
/// The provider polls [readTelemetry]; this class has no timer of its own.
class VaillantEbusdController implements HeatingController {
  VaillantEbusdConfig _config;
  bool _isConnected = false;

  final StreamController<ControllerTelemetry> _telemetryController =
      StreamController<ControllerTelemetry>.broadcast();

  HttpClient? _httpClient;

  /// circuit (lower case) → message name (lower case) → name as ebusd spells it.
  final Map<String, Map<String, String>> _messages = {};
  final Map<String, String> _circuits = {};

  static const _boiler = 'bai';
  static const _maxAgeSeconds = 60;

  VaillantEbusdController({
    VaillantEbusdConfig? config,
    HttpClient? httpClient,
  })  : _config = config ?? const VaillantEbusdConfig(),
        _httpClient = httpClient;

  VaillantEbusdConfig get config => _config;

  void updateConfig(VaillantEbusdConfig config) {
    _config = config;
    _messages.clear();
    _circuits.clear();
  }

  /// The regulator circuit (700, ctlv2, 470 …); null when only the boiler is configured.
  String? get _regulator {
    final c = _config.circuit.trim().toLowerCase();
    return c.isEmpty || c == _boiler ? null : c;
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
  HeatingCapabilities get capabilities => HeatingCapabilities(
        supportsHeatingCurveShift: false,
        supportsRoomTarget: _regulator != null,
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

  Duration get _timeout => Duration(seconds: _config.timeoutSeconds);

  HttpClient _getClient() {
    return _httpClient ??= HttpClient()
      ..connectionTimeout = _timeout
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
      await _loadMessageIndex();
      _isConnected = true;
      final initial = await readTelemetry();
      _telemetryController.add(initial);
    } catch (e) {
      await disconnect();
      if (e is ModbusCommunicationException) rethrow;
      throw ModbusCommunicationException(
        message: 'Verbindung zu ebusd fehlgeschlagen: $e',
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
    _messages.clear();
    _circuits.clear();
  }

  /// HTTP GET on the ebusd JSON port; null on a non-200 answer.
  Future<dynamic> _httpGet(String endpoint) async {
    final req = await _getClient().getUrl(_config.getUri(endpoint)).timeout(_timeout);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    // ebusd itself has no token; this is only for a reverse proxy in front of it.
    if (_config.apiToken.trim().isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiToken.trim()}');
    }
    final resp = await req.close().timeout(_timeout);
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return null;
    }
    final body = await resp.transform(utf8.decoder).join().timeout(_timeout);
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  /// Reads the message list once per connection: it tells which circuits and
  /// messages this installation has and how ebusd spells them (the Vaillant
  /// configuration changed e.g. z1DayTemp → Z1DayTemp).
  Future<void> _loadMessageIndex() async {
    dynamic data;
    try {
      data = await _httpGet('/data');
    } catch (e) {
      throw ModbusCommunicationException(
        message: 'ebusd unter ${_config.baseUrl} nicht erreichbar. Der HTTP-Port ist bei ebusd ab Werk aus '
            'und muss mit --httpport eingeschaltet werden. ($e)',
        underlyingError: e,
      );
    }
    if (data is! Map || !data.containsKey('global')) {
      throw ModbusCommunicationException(
        message: 'Unter ${_config.baseUrl} antwortet kein ebusd (JSON ohne „global“).',
      );
    }
    _messages.clear();
    _circuits.clear();
    data.forEach((circuit, value) {
      final messages = value is Map ? value['messages'] : null;
      if (circuit is! String || messages is! Map) return;
      _circuits[circuit.toLowerCase()] = circuit;
      _messages[circuit.toLowerCase()] = {
        for (final name in messages.keys.whereType<String>()) name.toLowerCase(): name,
      };
    });
    if (!_messages.containsKey(_boiler) && (_regulator == null || !_messages.containsKey(_regulator))) {
      throw ModbusCommunicationException(
        message: 'ebusd kennt weder den Kreis „$_boiler“ noch „${_config.circuit}“. '
            'Bekannte Kreise: ${_circuits.values.where((c) => c != 'global').join(', ')}.',
      );
    }
  }

  /// First of [names] that exists in [circuit], as `(circuit, name)` in ebusd's spelling.
  (String, String)? _find(String? circuit, List<String> names) {
    if (circuit == null) return null;
    final known = _messages[circuit];
    if (known == null) return null;
    for (final name in names) {
      final actual = known[name.toLowerCase()];
      if (actual != null) return (_circuits[circuit]!, actual);
    }
    return null;
  }

  (String, String)? get _roomTargetMessage => _find(_regulator, const ['Z1DayTemp', 'Hc1DayTemp']);

  /// Numeric value of one ebusd message; null if unknown, not yet read, or
  /// its sensor reports a fault.
  Future<double?> _readMessage((String, String)? message) async {
    if (message == null) return null;
    final (circuit, name) = message;
    dynamic data;
    try {
      data = await _httpGet('/data/$circuit/$name?maxage=$_maxAgeSeconds');
    } catch (e) {
      debugPrint('[VaillantEbusd] $circuit/$name: $e');
      return null;
    }
    final messages = data is Map && data[circuit] is Map ? (data[circuit] as Map)['messages'] : null;
    final entry = messages is Map ? messages[name] : null;
    return fieldValue(entry is Map ? entry['fields'] : null);
  }

  /// Picks the temperature out of an ebusd `fields` object, e.g.
  /// `{"temp": {"value": 48.5}, "sensor": {"value": "ok"}}`.
  @visibleForTesting
  static double? fieldValue(dynamic fields) {
    if (fields is! Map) return null;
    final sensor = fields['sensor'];
    final status = sensor is Map ? sensor['value'] : null;
    if (status is String && status.toLowerCase() != 'ok') return null;
    num? number(dynamic field) {
      final v = field is Map ? field['value'] : null;
      return v is num ? v : null;
    }

    final preferred = number(fields['temp']) ?? number(fields['temp1']) ?? number(fields['0']);
    if (preferred != null) return preferred.toDouble();
    for (final field in fields.values) {
      final n = number(field);
      if (n != null) return n.toDouble();
    }
    return null;
  }

  @override
  Future<ControllerTelemetry> readTelemetry() async {
    if (_messages.isEmpty) await _loadMessageIndex();

    final outdoor = await _readMessage(
        _find(_boiler, const ['OutdoorstempSensor']) ?? _find(_regulator, const ['DisplayedOutsideTemp']));
    final flow = await _readMessage(_find(_boiler, const ['FlowTemp']));
    final ret = await _readMessage(_find(_boiler, const ['ReturnTemp']));
    final hotWater = await _readMessage(_find(_boiler, const ['StorageTemp', 'HwcTemp']));
    final room = await _readMessage(_roomTargetMessage);

    if (outdoor == null && flow == null && ret == null && hotWater == null && room == null) {
      throw const ModbusCommunicationException(
        message: 'ebusd liefert für keine der erwarteten Vaillant-Meldungen einen Wert '
            '(FlowTemp, ReturnTemp, OutdoorstempSensor, StorageTemp).',
      );
    }

    return ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoor,
      flowTemp: flow,
      returnTemp: ret,
      hotWaterTemp: hotWater,
      roomTarget: room,
      rawValues: {
        'outdoor': ?outdoor,
        'flow': ?flow,
        'return': ?ret,
        'hotWater': ?hotWater,
        'roomTarget': ?room,
      },
    );
  }

  /// Sends one line to ebusd's TCP command port and returns the answer
  /// (ebusd ends every answer with an empty line).
  Future<String> _command(String line) async {
    final socket = await Socket.connect(_config.host, _config.commandPort, timeout: _timeout);
    try {
      socket.write('$line\n');
      await socket.flush();
      final buffer = StringBuffer();
      final done = Completer<void>();
      final sub = socket.listen(
        (data) {
          buffer.write(utf8.decode(data, allowMalformed: true));
          if (buffer.toString().contains('\n\n') && !done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      // Writes wait for the bus; give them more time than a plain read.
      await done.future.timeout(_timeout * 3, onTimeout: () {});
      await sub.cancel();
      return buffer.toString().trim();
    } finally {
      socket.destroy();
    }
  }

  @override
  Future<void> setHeatingCurveShift(double shift) async {
    throw const ModbusCommunicationException(
      message: 'Vaillant-Regler haben über ebusd keine Parallelverschiebung. '
          'Stattdessen die Raum-Solltemperatur ändern.',
    );
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    if (!_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine aktive Verbindung zu ebusd.',
      );
    }
    final message = _roomTargetMessage;
    if (message == null) {
      throw ModbusCommunicationException(
        message: 'ebusd kennt im Kreis „${_config.circuit}“ keine Raum-Solltemperatur '
            '(Z1DayTemp / Hc1DayTemp).',
      );
    }
    final (circuit, name) = message;
    String answer;
    try {
      answer = await _command('write -c $circuit $name ${temperature.fixed(1)}');
    } catch (e) {
      throw ModbusCommunicationException(
        message: 'ebusd-Befehlsport ${_config.host}:${_config.commandPort} nicht erreichbar – '
            'Schreiben geht bei ebusd nur über diesen Port. ($e)',
        underlyingError: e,
      );
    }
    if (!answer.toLowerCase().startsWith('done')) {
      throw ModbusCommunicationException(
        message: 'ebusd hat die Raum-Solltemperatur (${temperature.de(1)} °C) nicht übernommen: '
            '${answer.isEmpty ? "keine Antwort" : answer}',
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
      final telemetry = await controller.readTelemetry();
      return {
        'success': true,
        'message': 'ebusd erreicht und Werte gelesen.',
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
        'message': e is ModbusCommunicationException ? e.message : 'ebusd-Verbindungstest fehlgeschlagen: $e',
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
