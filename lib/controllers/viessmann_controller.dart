import 'package:heizungstrainer/utils/number_format.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';

/// Heating controller adapter for Viessmann heating systems.
///
/// Two backends, both NOT verified on hardware:
/// 1. [ViessmannConnectionType.optolinkTcp]: a vcontrold daemon (openv) on the
///    LAN. Text protocol on TCP 3002: the server sends the prompt `vctrld>`
///    after connect and after every answer; errors start with `ERR:`. The
///    command names come from the vito.xml shipped with vcontrold
///    (getTempA, getTempVListM1, getTempRL17A, getTempWWist,
///    getTempRaumNorSollM1, getNiveauM1 and the matching set… commands);
///    installations with a customised vito.xml may use other names.
/// 2. [ViessmannConnectionType.vicareRest]: Viessmann cloud API v2
///    (paths as used by the open-source PyViCare client). The access token
///    from the developer portal is valid for about one hour; the app has no
///    OAuth refresh, so this is only usable for short sessions.
///
/// The provider polls [readTelemetry]; this class has no timer of its own.
class ViessmannController implements HeatingController {
  ViessmannConfig _config;
  bool _isConnected = false;

  final StreamController<ControllerTelemetry> _telemetryController =
      StreamController<ControllerTelemetry>.broadcast();

  /// Overridable for tests.
  final String vicareBaseUrl;
  final String vicareTokenUrl;

  /// Called after the access token was renewed, so the owner can persist the
  /// new token (and a rotated refresh token, should Viessmann send one).
  void Function(ViessmannConfig config)? onTokenRefreshed;

  HttpClient? _httpClient;
  DateTime? _lastVicarePoll;
  ControllerTelemetry? _cachedVicareTelemetry;
  _VicareDevice? _vicareDevice;
  double? _vicareSlope;

  ViessmannController({
    ViessmannConfig? config,
    this.vicareBaseUrl = 'https://api.viessmann-climatesolutions.com/iot/v2',
    this.vicareTokenUrl = 'https://iam.viessmann-climatesolutions.com/idp/v3/token',
    this.onTokenRefreshed,
  }) : _config = config ?? const ViessmannConfig();

  ViessmannConfig get config => _config;

  void updateConfig(ViessmannConfig config) {
    _config = config;
    _vicareDevice = null;
    _invalidateVicareCache();
  }

  bool get _isOptolink => _config.connectionType == ViessmannConnectionType.optolinkTcp;

  @override
  String get id => 'viessmann_vicare';

  @override
  String get brandName => 'Viessmann';

  @override
  String get modelName => 'Vitotronic & ViCare';

  @override
  ConnectionProtocol get protocol =>
      _isOptolink ? ConnectionProtocol.proprietary : ConnectionProtocol.restApi;

  @override
  HeatingCapabilities get capabilities => const HeatingCapabilities(
        supportsHeatingCurveShift: true,
        // Viessmann "Niveau": −13…40 K; the app never needs more than ±13.
        minShift: -13.0,
        maxShift: 13.0,
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
      ..connectionTimeout = Duration(seconds: _config.timeoutSeconds);
  }

  Duration get _timeout => Duration(seconds: _config.timeoutSeconds);

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
    _vicareDevice = null;
    _invalidateVicareCache();

    try {
      _isConnected = true;
      // The first read proves the daemon / API answers with usable values.
      final initial = await readTelemetry();
      _telemetryController.add(initial);
    } catch (e) {
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
    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = null;
    _isConnected = false;
  }

  // ──────────────────────────────────────────────────────────────────
  // Local Optolink (vcontrold text protocol)
  // ──────────────────────────────────────────────────────────────────

  static const _prompt = 'vctrld>';

  /// Heating circuit suffix of the vito.xml command names (circuit 0 → M1).
  String get _m => 'M${(int.tryParse(_config.circuit) ?? 0) + 1}';

  /// Runs [commands] in ONE vcontrold session: wait for the prompt, send a
  /// command, read up to the next prompt, …, `quit`. Returns the answer text
  /// per command (without prompt).
  Future<List<String>> _optolinkSession(List<String> commands) async {
    Socket socket;
    try {
      socket = await Socket.connect(_config.host, _config.port, timeout: _timeout);
    } catch (e) {
      throw ModbusCommunicationException(
        message: 'vcontrold unter ${_config.host}:${_config.port} nicht erreichbar: $e',
        underlyingError: e,
      );
    }

    final buffer = StringBuffer();
    Completer<void>? wake;
    var done = false;
    final sub = socket.listen(
      (data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
        wake?.complete();
        wake = null;
      },
      onError: (Object _) {
        done = true;
        wake?.complete();
        wake = null;
      },
      onDone: () {
        done = true;
        wake?.complete();
        wake = null;
      },
      cancelOnError: true,
    );

    Future<String> readToPrompt() async {
      final deadline = DateTime.now().add(_timeout);
      while (true) {
        final text = buffer.toString();
        final at = text.indexOf(_prompt);
        if (at >= 0) {
          buffer
            ..clear()
            ..write(text.substring(at + _prompt.length));
          return text.substring(0, at).trim();
        }
        final left = deadline.difference(DateTime.now());
        if (done || left <= Duration.zero) {
          throw ModbusCommunicationException(
            message: 'vcontrold unter ${_config.host}:${_config.port} antwortet nicht mit dem '
                'erwarteten Prompt – läuft dort wirklich vcontrold?',
          );
        }
        wake = Completer<void>();
        await wake!.future.timeout(left, onTimeout: () {});
      }
    }

    try {
      await readToPrompt(); // greeting prompt
      final answers = <String>[];
      for (final cmd in commands) {
        socket.write('$cmd\n');
        await socket.flush();
        answers.add(await readToPrompt());
      }
      try {
        socket.write('quit\n');
        await socket.flush();
      } catch (_) {}
      return answers;
    } finally {
      await sub.cancel();
      socket.destroy();
    }
  }

  static bool _isOptolinkError(String answer) =>
      answer.isEmpty || answer.toUpperCase().startsWith('ERR');

  double? _parseOptolinkNumber(String answer) {
    if (_isOptolinkError(answer)) return null;
    final match = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(answer);
    if (match == null) return null;
    return double.tryParse(match.group(0)!.replaceAll(',', '.'));
  }

  Future<ControllerTelemetry> _readOptolinkTelemetry() async {
    final answers = await _optolinkSession([
      'getTempA',
      'getTempVList$_m',
      'getTempKist',
      'getTempRL17A',
      'getTempWWist',
      'getTempRaumNorSoll$_m',
      'getNiveau$_m',
    ]);
    final outdoor = _parseOptolinkNumber(answers[0]);
    // Circuits without mixer have no own flow sensor → boiler temperature.
    final flow = _parseOptolinkNumber(answers[1]) ?? _parseOptolinkNumber(answers[2]);
    final returnT = _parseOptolinkNumber(answers[3]);
    final hotWater = _parseOptolinkNumber(answers[4]);
    final room = _parseOptolinkNumber(answers[5]);
    final shift = _parseOptolinkNumber(answers[6]);

    if (outdoor == null && flow == null && returnT == null && hotWater == null) {
      throw ModbusCommunicationException(
        message: 'vcontrold kennt die Standard-Kommandos nicht (Antwort: „${answers[0]}“). '
            'Die App erwartet die Kommandonamen der mitgelieferten vito.xml.',
      );
    }

    return ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoor,
      flowTemp: flow,
      returnTemp: returnT,
      hotWaterTemp: hotWater,
      roomTarget: room,
      heatingCurveShift: shift,
      rawValues: {
        'outdoor': ?outdoor,
        'flow': ?flow,
        'return': ?returnT,
        'hotWater': ?hotWater,
        'roomTarget': ?room,
        'shift': ?shift,
      },
    );
  }

  Future<void> _optolinkWrite(String command, String label) async {
    final answer = (await _optolinkSession([command])).single;
    if (_isOptolinkError(answer)) {
      throw ModbusCommunicationException(
        message: 'Viessmann Optolink: $label konnte nicht gesetzt werden: '
            '${answer.isEmpty ? "keine Antwort" : answer}',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Viessmann cloud API v2
  // ──────────────────────────────────────────────────────────────────

  /// After a write the next read must hit the API, otherwise the cache
  /// returns the old value and the provider's read-back check fails.
  void _invalidateVicareCache() {
    _cachedVicareTelemetry = null;
    _lastVicarePoll = null;
  }

  /// One feature list per interval: the free developer quota is 1450 calls
  /// per 24 h, and the provider polls every 10 s.
  Duration get _vicareCacheTime =>
      Duration(seconds: _config.cloudPollingIntervalSeconds.clamp(75, 300));

  /// Exchanges the refresh token for a new access token (valid one hour).
  Future<void> _refreshVicareToken() async {
    final req = await _getClient().postUrl(Uri.parse(vicareTokenUrl)).timeout(_timeout);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    req.write(Uri(queryParameters: {
      'grant_type': 'refresh_token',
      'client_id': _config.clientId.trim(),
      'refresh_token': _config.refreshToken.trim(),
    }).query);
    final resp = await req.close().timeout(_timeout);
    final text = await resp.transform(utf8.decoder).join().timeout(_timeout);
    dynamic json;
    try {
      json = jsonDecode(text);
    } catch (_) {}
    final token = json is Map ? json['access_token'] : null;
    if (resp.statusCode != 200 || token is! String || token.isEmpty) {
      throw ModbusCommunicationException(
        message: 'ViCare-Zugang konnte nicht erneuert werden (Status ${resp.statusCode}). '
            'Client-ID und Refresh-Token in den Einstellungen prüfen – ein Refresh-Token gilt etwa 180 Tage.',
      );
    }
    final rotated = json['refresh_token'];
    _config = _config.copyWith(
      apiToken: token,
      refreshToken: rotated is String && rotated.isNotEmpty ? rotated : null,
    );
    onTokenRefreshed?.call(_config);
  }

  Future<dynamic> _vicareRequest(String method, String path, {Object? body, bool retried = false}) async {
    if (_config.apiToken.trim().isEmpty && _config.canRefreshToken && !retried) {
      await _refreshVicareToken();
    }
    final req = await _getClient().openUrl(method, Uri.parse('$vicareBaseUrl$path')).timeout(_timeout);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiToken.trim()}');
    if (body != null) {
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode(body));
    }
    final resp = await req.close().timeout(_timeout);
    final text = await resp.transform(utf8.decoder).join().timeout(_timeout);
    dynamic json;
    try {
      json = text.trim().isEmpty ? null : jsonDecode(text);
    } catch (_) {}
    final error = json is Map ? '${json['error'] ?? json['errorType'] ?? ''}' : '';
    final expired = resp.statusCode == 401 || error.toUpperCase().contains('EXPIRED');
    if (expired && _config.canRefreshToken && !retried) {
      await _refreshVicareToken();
      return _vicareRequest(method, path, body: body, retried: true);
    }
    if (expired || resp.statusCode == 403) {
      throw ModbusCommunicationException(
        message: _config.canRefreshToken
            ? 'ViCare hat den Zugang auch mit frisch erneuertem Token abgelehnt. '
                'Client-ID, Refresh-Token und die Freigabe der Anlage im Viessmann-Konto prüfen.'
            : 'ViCare hat den API-Token abgelehnt. Access-Tokens gelten nur etwa eine Stunde – '
                'in den Einstellungen Client-ID und Refresh-Token hinterlegen, dann erneuert die App ihn selbst.',
      );
    }
    if (resp.statusCode == 429) {
      throw const ModbusCommunicationException(
        message: 'ViCare-Tageskontingent erschöpft (1450 Abfragen in 24 Stunden). Später erneut versuchen.',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ModbusCommunicationException(
        message: 'Viessmann-API antwortet mit Status ${resp.statusCode}'
            '${json is Map && json['message'] != null ? ': ${json['message']}' : ''}',
      );
    }
    return json;
  }

  /// Installation → gateway serial → device id of the heating device.
  Future<_VicareDevice> _resolveVicareDevice() async {
    final cached = _vicareDevice;
    if (cached != null) return cached;
    final json = await _vicareRequest('GET', '/equipment/installations?includeGateways=true');
    final installations = (json is Map ? json['data'] : null) as List<dynamic>? ?? const [];
    final wanted = _config.installationId.trim();
    for (final inst in installations.whereType<Map>()) {
      final instId = '${inst['id']}';
      if (wanted.isNotEmpty && instId != wanted) continue;
      for (final gw in (inst['gateways'] as List<dynamic>? ?? const []).whereType<Map>()) {
        final devices = (gw['devices'] as List<dynamic>? ?? const []).whereType<Map>().toList();
        if (devices.isEmpty) continue;
        final device = devices.firstWhere(
          (d) => d['deviceType'] == 'heating',
          orElse: () => devices.firstWhere((d) => '${d['id']}' == '0', orElse: () => devices.first),
        );
        return _vicareDevice = _VicareDevice(instId, '${gw['serial']}', '${device['id']}');
      }
    }
    throw ModbusCommunicationException(
      message: wanted.isEmpty
          ? 'Im ViCare-Konto wurde keine Anlage mit Heizgerät gefunden.'
          : 'Die Anlage $wanted wurde im ViCare-Konto nicht gefunden.',
    );
  }

  Future<ControllerTelemetry> _readVicareTelemetry() async {
    final now = DateTime.now();
    if (_lastVicarePoll != null &&
        now.difference(_lastVicarePoll!) < _vicareCacheTime &&
        _cachedVicareTelemetry != null) {
      return _cachedVicareTelemetry!;
    }

    final device = await _resolveVicareDevice();
    final json = await _vicareRequest('GET', '${device.path}/features/');
    _lastVicarePoll = now;

    final features = <String, Map<dynamic, dynamic>>{};
    for (final item in ((json is Map ? json['data'] : null) as List<dynamic>? ?? const []).whereType<Map>()) {
      final props = item['properties'];
      if (item['feature'] is String && props is Map) features[item['feature'] as String] = props;
    }
    double? value(String feature, [String property = 'value']) {
      final v = features[feature]?[property];
      final n = v is Map ? v['value'] : null;
      return n is num ? n.toDouble() : null;
    }

    final c = 'heating.circuits.${_config.circuit}';
    final outdoor = value('heating.sensors.temperature.outside');
    final flow = value('$c.sensors.temperature.supply') ??
        value('heating.boiler.sensors.temperature.commonSupply') ??
        value('heating.boiler.sensors.temperature.main');
    final returnT = value('heating.sensors.temperature.return');
    final hotWater = value('heating.dhw.sensors.temperature.dhwCylinder') ??
        value('heating.dhw.sensors.temperature.hotWaterStorage');
    final room = value('$c.operating.programs.normal', 'temperature');
    final shift = value('$c.heating.curve', 'shift');
    _vicareSlope = value('$c.heating.curve', 'slope') ?? _vicareSlope;

    final telemetry = ControllerTelemetry(
      timestamp: DateTime.now(),
      outdoorTemp: outdoor,
      flowTemp: flow,
      returnTemp: returnT,
      hotWaterTemp: hotWater,
      roomTarget: room,
      heatingCurveShift: shift,
      rawValues: {
        'outdoor': ?outdoor,
        'flow': ?flow,
        'return': ?returnT,
        'hotWater': ?hotWater,
        'roomTarget': ?room,
        'shift': ?shift,
      },
    );

    _cachedVicareTelemetry = telemetry;
    return telemetry;
  }

  Future<void> _vicareCommand(String feature, String command, Map<String, dynamic> body) async {
    final device = await _resolveVicareDevice();
    await _vicareRequest('POST', '${device.path}/features/$feature/commands/$command', body: body);
    _invalidateVicareCache();
  }

  // ──────────────────────────────────────────────────────────────────
  // Telemetry & setpoints
  // ──────────────────────────────────────────────────────────────────

  @override
  Future<ControllerTelemetry> readTelemetry() =>
      _isOptolink ? _readOptolinkTelemetry() : _readVicareTelemetry();

  void _requireConnected() {
    if (!_isConnected) {
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum Viessmann Regler.',
      );
    }
  }

  @override
  Future<void> setHeatingCurveShift(double shift) async {
    _requireConnected();
    if (_isOptolink) {
      await _optolinkWrite('setNiveau$_m ${shift.round()}', 'Parallelverschiebung');
      return;
    }
    // setCurve always needs shift AND slope; the slope must stay as it is.
    if (_vicareSlope == null) {
      _invalidateVicareCache();
      await _readVicareTelemetry();
    }
    final slope = _vicareSlope;
    if (slope == null) {
      throw const ModbusCommunicationException(
        message: 'ViCare: Die aktuelle Neigung der Heizkurve ist nicht lesbar – '
            'ohne sie kann die Parallelverschiebung nicht gesetzt werden.',
      );
    }
    await _vicareCommand(
      'heating.circuits.${_config.circuit}.heating.curve',
      'setCurve',
      {'shift': shift.round(), 'slope': slope},
    );
  }

  @override
  Future<void> setRoomTarget(double temperature) async {
    _requireConnected();
    if (_isOptolink) {
      await _optolinkWrite('setTempRaumNorSoll$_m ${temperature.fixed(1)}', 'Raum-Sollwert');
      return;
    }
    await _vicareCommand(
      'heating.circuits.${_config.circuit}.operating.programs.normal',
      'setTemperature',
      {'targetTemperature': temperature},
    );
  }

  /// Diagnostic connection test for settings screen.
  static Future<Map<String, dynamic>> testConnection(ViessmannConfig config) async {
    final controller = ViessmannController(config: config);
    final optolink = config.connectionType == ViessmannConnectionType.optolinkTcp;
    try {
      final telemetry = await controller.readTelemetry();
      return {
        'success': true,
        'message': optolink ? 'vcontrold erreicht und Werte gelesen.' : 'Viessmann-API erreicht und Werte gelesen.',
        'type': optolink ? 'Optolink TCP (${config.host}:${config.port})' : 'ViCare Cloud REST API',
        'outdoorTemp': telemetry.outdoorTemp,
        'flowTemp': telemetry.flowTemp,
        'returnTemp': telemetry.returnTemp,
        'hotWaterTemp': telemetry.hotWaterTemp,
        'roomTarget': telemetry.roomTarget,
      };
    } catch (e) {
      return {
        'success': false,
        'message': e is ModbusCommunicationException ? e.message : 'Viessmann Verbindungstest fehlgeschlagen: $e',
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

class _VicareDevice {
  final String installationId;
  final String gatewaySerial;
  final String deviceId;
  const _VicareDevice(this.installationId, this.gatewaySerial, this.deviceId);

  String get path => '/features/installations/$installationId/gateways/$gatewaySerial/devices/$deviceId';
}
