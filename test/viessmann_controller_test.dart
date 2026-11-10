import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';
import 'package:heizungstrainer/controllers/viessmann_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

class _AllowLocalHttpOverrides extends HttpOverrides {}

/// Imitates the vcontrold daemon (openv) on its TCP port:
/// - sends the prompt `vctrld>` (no newline) right after connect,
/// - answers every command line with `<answer>\n` followed by the prompt,
/// - unknown commands answer `ERR: command unknown`,
/// - `quit` answers `good bye!` and closes the connection.
class MockVcontrold {
  static const prompt = 'vctrld>';

  /// get-commands of the vito.xml and their current values.
  final Map<String, double> values = {
    'getTempA': 4.8,
    'getTempVListM1': 47.5,
    'getTempKist': 61.0,
    'getTempRL17A': 39.0,
    'getTempWWist': 54.2,
    'getTempRaumNorSollM1': 20.0,
    'getNiveauM1': 1.0,
  };

  /// set-commands this vito.xml knows → the get-command they change.
  final Map<String, String> setters = {
    'setTempRaumNorSollM1': 'getTempRaumNorSollM1',
    'setNiveauM1': 'getNiveauM1',
  };

  /// Send every piece (answer, half prompts) as its own delayed socket write.
  bool fragmented = false;

  /// Accept connections but never say anything (e.g. another service on the port).
  bool silent = false;

  /// Command lines received, one list per TCP session.
  final List<List<String>> sessions = [];

  late final ServerSocket _server;
  final List<Socket> _sockets = [];

  int get port => _server.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> stop() async {
    for (final s in _sockets) {
      s.destroy();
    }
    await _server.close();
  }

  Future<void> _send(Socket socket, List<String> pieces) async {
    if (!fragmented) {
      socket.write(pieces.join());
      return;
    }
    for (final piece in pieces) {
      socket.write(piece);
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
  }

  Future<void> _sendPrompt(Socket socket) => _send(socket, ['vct', 'rld>']);

  String _answer(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    final command = parts.first;
    if (values.containsKey(command) && parts.length == 1) {
      final unit = command.startsWith('getNiveau') ? 'K' : 'Grad Celsius';
      return '${values[command]!.toStringAsFixed(6)} $unit';
    }
    final target = setters[command];
    final argument = parts.length == 2 ? double.tryParse(parts[1]) : null;
    if (target != null && argument != null) {
      values[target] = argument;
      return 'OK';
    }
    return 'ERR: command unknown';
  }

  Future<void> _serve(Socket socket) async {
    _sockets.add(socket);
    final session = <String>[];
    sessions.add(session);
    try {
      if (silent) {
        await socket.drain<void>();
        return;
      }
      await _sendPrompt(socket);
      // Commands may arrive split over several TCP segments: work on lines.
      final lines = socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        session.add(line);
        if (line.trim() == 'quit') {
          socket.write('good bye!\n');
          await socket.flush();
          break;
        }
        await _send(socket, ['${_answer(line)}\n']);
        await _sendPrompt(socket);
      }
    } catch (_) {
      // client went away
    } finally {
      socket.destroy();
    }
  }
}

/// Imitates the Viessmann IoT API v2 for one installation with one gateway.
class MockVicareApi {
  static const token = 'valid-access-token';
  static const _device = '/features/installations/123/gateways/7571381573112225/devices/0';

  double roomTarget = 21.0;
  int shift = 2;
  num slope = 1.4;

  /// When set, every request is answered with this status (401, 429 …).
  int? failWith;

  /// "METHOD /path?query" of every request.
  final List<String> requests = [];

  /// Decoded JSON bodies of the command POSTs, by command name.
  final Map<String, dynamic> commandBodies = {};

  late final HttpServer _server;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  int count(String needle) => requests.where((r) => r.contains(needle)).length;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> stop() => _server.close(force: true);

  Map<String, dynamic> _feature(String name, Map<String, dynamic> properties) => {
        'feature': name,
        'gatewayId': '7571381573112225',
        'deviceId': '0',
        'isEnabled': true,
        'properties': properties,
      };

  Map<String, dynamic> _number(num value, [String unit = 'celsius']) =>
      {'type': 'number', 'unit': unit, 'value': value};

  Future<void> _reply(HttpRequest request, int status, Object body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    requests.add('${request.method} ${request.uri}');
    final body = await utf8.decodeStream(request);

    if (failWith == 429) {
      return _reply(request, 429, {
        'viErrorId': 'req-1',
        'statusCode': 429,
        'errorType': 'RATE_LIMIT_EXCEEDED',
        'message': 'API calls rate limit has been exceeded.',
      });
    }
    if (failWith == 401 || request.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $token') {
      return _reply(request, 401, {
        'viErrorId': 'req-1',
        'statusCode': 401,
        'errorType': 'UNAUTHORIZED',
        'message': 'UNAUTHORIZED',
        'error': 'EXPIRED TOKEN',
      });
    }

    if (request.method == 'GET' &&
        path == '/equipment/installations' &&
        request.uri.queryParameters['includeGateways'] == 'true') {
      return _reply(request, 200, {
        'data': [
          {
            'id': 123,
            'gateways': [
              {
                'serial': '7571381573112225',
                'devices': [
                  {'id': 'gateway', 'deviceType': 'vitoconnect'},
                  {'id': '0', 'deviceType': 'heating'},
                ],
              },
            ],
          },
        ],
      });
    }

    if (request.method == 'GET' && path == '$_device/features/') {
      return _reply(request, 200, {
        'data': [
          _feature('heating.sensors.temperature.outside', {'value': _number(4.8)}),
          _feature('heating.circuits.0.sensors.temperature.supply', {'value': _number(47.5)}),
          _feature('heating.sensors.temperature.return', {'value': _number(39.0)}),
          _feature('heating.dhw.sensors.temperature.dhwCylinder', {'value': _number(54.2)}),
          _feature('heating.circuits.0.operating.programs.normal', {
            'active': {'type': 'boolean', 'value': true},
            'temperature': _number(roomTarget),
          }),
          _feature('heating.circuits.0.heating.curve', {
            'shift': _number(shift, 'kelvin'),
            'slope': _number(slope, ''),
          }),
          // A feature without properties, as the real list has many.
          _feature('heating.circuits.1', {}),
        ],
      });
    }

    const commands = {
      '$_device/features/heating.circuits.0.heating.curve/commands/setCurve': 'setCurve',
      '$_device/features/heating.circuits.0.operating.programs.normal/commands/setTemperature': 'setTemperature',
    };
    final command = commands[path];
    if (request.method == 'POST' && command != null) {
      final json = jsonDecode(body) as Map<String, dynamic>;
      commandBodies[command] = json;
      if (command == 'setCurve') {
        shift = json['shift'] as int;
        slope = json['slope'] as num;
      } else {
        roomTarget = (json['targetTemperature'] as num).toDouble();
      }
      return _reply(request, 200, {
        'data': {'success': true, 'reason': 'COMMAND_EXECUTION_SUCCESS'},
      });
    }

    return _reply(request, 404, {
      'statusCode': 404,
      'errorType': 'RESOURCE_NOT_FOUND',
      'message': 'not found',
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowLocalHttpOverrides();

  final throwsModbusError = throwsA(isA<ModbusCommunicationException>());

  group('ViessmannConfig & Presets Tests', () {
    test('only vcontrold and the cloud API are left as presets', () {
      expect(ViessmannConfig.presets.map((p) => p.id), ['optolink_vcontrold', 'vicare_cloud']);
      expect(ViessmannConfig.presets[0].connectionType, ViessmannConnectionType.optolinkTcp);
      expect(ViessmannConfig.presets[0].defaultPort, 3002);
      expect(ViessmannConfig.presets[1].connectionType, ViessmannConnectionType.vicareRest);
    });

    test('default config values are valid', () {
      const config = ViessmannConfig();
      expect(config.host, '192.168.1.130');
      expect(config.port, 3002);
      expect(config.circuit, '0');
      expect(config.connectionType, ViessmannConnectionType.optolinkTcp);
      expect(config.apiToken, isEmpty);
      expect(config.presetId, 'optolink_vcontrold');
    });

    test('toJson and fromJson preserves all fields', () {
      const original = ViessmannConfig(
        connectionType: ViessmannConnectionType.vicareRest,
        host: 'api.viessmann.com',
        port: 443,
        apiToken: 'secret_vicare_token',
        installationId: 'install_9876',
        circuit: '1',
        timeoutSeconds: 7,
        cloudPollingIntervalSeconds: 120,
        presetId: 'vicare_cloud',
        presetName: 'Viessmann ViCare API (Cloud)',
      );

      final restored = ViessmannConfig.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
    });

    test('fromJson derives the preset from the connection type (removed preset ids disappear)', () {
      for (final oldId in ['esp_optolink', 'vitotronic_200', 'custom']) {
        final local = ViessmannConfig.fromJson({
          'connectionType': 'optolinkTcp',
          'host': '192.168.1.99',
          'port': 7362,
          'presetId': oldId,
          'presetName': 'Something old',
        });
        expect(local.presetId, 'optolink_vcontrold', reason: oldId);
        expect(local.presetName, 'Viessmann Optolink (vcontrold)');
        expect(local.host, '192.168.1.99');
        expect(local.port, 7362);

        final cloud = ViessmannConfig.fromJson({'connectionType': 'vicareRest', 'presetId': oldId});
        expect(cloud.presetId, 'vicare_cloud', reason: oldId);
        expect(cloud.presetName, 'Viessmann ViCare API (Cloud)');
      }
    });

    test('copyWith properly updates specific properties', () {
      const base = ViessmannConfig();
      final updated = base.copyWith(
        host: '192.168.178.70',
        port: 7362,
        circuit: '1',
      );

      expect(updated.host, '192.168.178.70');
      expect(updated.port, 7362);
      expect(updated.circuit, '1');
      expect(updated.connectionType, base.connectionType);
    });

    test('secure storage save and load cycle', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      final initial = await ViessmannConfig.load(storage);
      expect(initial.presetId, 'optolink_vcontrold');

      await initial
          .copyWith(
            connectionType: ViessmannConnectionType.vicareRest,
            apiToken: 'abc',
            installationId: '123',
          )
          .save(storage);

      final loaded = await ViessmannConfig.load(storage);
      expect(loaded.connectionType, ViessmannConnectionType.vicareRest);
      expect(loaded.presetId, 'vicare_cloud');
      expect(loaded.apiToken, 'abc');
      expect(loaded.installationId, '123');
    });
  });

  group('ViessmannController basics', () {
    test('initial state and capabilities are correct', () {
      final controller = ViessmannController();

      expect(controller.id, 'viessmann_vicare');
      expect(controller.brandName, contains('Viessmann'));
      expect(controller.isConnected, isFalse);
      expect(controller.protocol, ConnectionProtocol.proprietary);
      expect(controller.capabilities.supportsHeatingCurveShift, isTrue);
      expect(controller.capabilities.supportsRoomTarget, isTrue);
      expect(controller.capabilities.supportsHotWater, isTrue);
      expect(controller.capabilities.supportsOutdoorTemp, isTrue);
      expect(controller.capabilities.supportsReturnTemp, isTrue);
    });

    test('disconnect when disconnected completes cleanly', () async {
      final controller = ViessmannController();
      await expectLater(controller.disconnect(), completes);
      expect(controller.isConnected, isFalse);
    });

    test('writes without a connection throw', () async {
      final controller = ViessmannController();
      await expectLater(controller.setRoomTarget(21.0), throwsModbusError);
      await expectLater(controller.setHeatingCurveShift(1.0), throwsModbusError);
    });
  });

  group('Optolink via vcontrold (text protocol)', () {
    late MockVcontrold vcontrold;

    setUp(() async {
      vcontrold = MockVcontrold();
      await vcontrold.start();
    });

    tearDown(() => vcontrold.stop());

    ViessmannConfig config({int timeoutSeconds = 2}) => ViessmannConfig(
          connectionType: ViessmannConnectionType.optolinkTcp,
          host: '127.0.0.1',
          port: vcontrold.port,
          circuit: '0',
          timeoutSeconds: timeoutSeconds,
        );

    test('reads telemetry in one TCP session', () async {
      final controller = ViessmannController(config: config());
      await controller.connect(host: '127.0.0.1', port: vcontrold.port);
      expect(controller.isConnected, isTrue);
      vcontrold.sessions.clear();

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 4.8);
      expect(telemetry.flowTemp, 47.5); // the circuit's own flow sensor, not the boiler (61.0)
      expect(telemetry.returnTemp, 39.0);
      expect(telemetry.hotWaterTemp, 54.2);
      expect(telemetry.roomTarget, 20.0);
      expect(telemetry.heatingCurveShift, 1.0);
      expect(telemetry.spread, closeTo(8.5, 0.01));

      // Let the server finish reading the session ("quit").
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(vcontrold.sessions, hasLength(1));
      final commands = vcontrold.sessions.single;
      expect(
        commands,
        containsAll([
          'getTempA',
          'getTempVListM1',
          'getTempRL17A',
          'getTempWWist',
          'getTempRaumNorSollM1',
          'getNiveauM1',
        ]),
      );
      expect(commands.last, 'quit');

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });

    test('prompt and answers arriving in separate TCP segments are not mis-parsed', () async {
      // Greeting prompt split in two writes, every answer and prompt in its own
      // write: a client that reads "whatever arrived" would pair the answers
      // with the wrong commands or take the lone prompt for an empty answer.
      vcontrold.fragmented = true;
      final controller = ViessmannController(config: config());
      await controller.connect(host: '127.0.0.1', port: vcontrold.port);

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 4.8);
      expect(telemetry.flowTemp, 47.5);
      expect(telemetry.returnTemp, 39.0);
      expect(telemetry.hotWaterTemp, 54.2);
      expect(telemetry.roomTarget, 20.0);
      expect(telemetry.heatingCurveShift, 1.0);

      await controller.setRoomTarget(22.0);
      expect(vcontrold.values['getTempRaumNorSollM1'], 22.0);
      await controller.disconnect();
    });

    test('falls back to the boiler temperature when the circuit has no flow sensor command', () async {
      vcontrold.values.remove('getTempVListM1'); // → ERR: command unknown
      final controller = ViessmannController(config: config());
      await controller.connect(host: '127.0.0.1', port: vcontrold.port);

      final telemetry = await controller.readTelemetry();
      expect(telemetry.flowTemp, 61.0); // getTempKist
      expect(telemetry.outdoorTemp, 4.8);
      expect(telemetry.returnTemp, 39.0);
      await controller.disconnect();
    });

    test('writes room setpoint (one decimal) and niveau (integer) and reads them back', () async {
      final controller = ViessmannController(config: config());
      await controller.connect(host: '127.0.0.1', port: vcontrold.port);
      vcontrold.sessions.clear();

      await controller.setRoomTarget(21.5);
      await controller.setHeatingCurveShift(3.0);
      await controller.setHeatingCurveShift(-2.0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vcontrold.sessions, [
        ['setTempRaumNorSollM1 21.5', 'quit'],
        ['setNiveauM1 3', 'quit'],
        ['setNiveauM1 -2', 'quit'],
      ]);

      final telemetry = await controller.readTelemetry();
      expect(telemetry.roomTarget, 21.5);
      expect(telemetry.heatingCurveShift, -2.0);
      await controller.disconnect();
    });

    test('a write answered with ERR throws instead of reporting success', () async {
      final controller = ViessmannController(config: config());
      await controller.connect(host: '127.0.0.1', port: vcontrold.port);

      vcontrold.setters.clear(); // this vito.xml has no set commands
      await expectLater(controller.setHeatingCurveShift(2.0), throwsModbusError);
      await expectLater(
        controller.setRoomTarget(22.0),
        throwsA(isA<ModbusCommunicationException>().having((e) => e.message, 'message', contains('ERR'))),
      );
      expect(vcontrold.values['getNiveauM1'], 1.0);
      expect(vcontrold.values['getTempRaumNorSollM1'], 20.0);
      await controller.disconnect();
    });

    test('a daemon that knows none of the commands is an error', () async {
      vcontrold.values.clear();
      final controller = ViessmannController(config: config());
      await expectLater(controller.connect(host: '127.0.0.1', port: vcontrold.port), throwsModbusError);
      expect(controller.isConnected, isFalse);
    });

    test('a server that never sends the prompt throws after the timeout', () async {
      vcontrold.silent = true;
      final controller = ViessmannController(config: config(timeoutSeconds: 1));

      final watch = Stopwatch()..start();
      await expectLater(controller.connect(host: '127.0.0.1', port: vcontrold.port), throwsModbusError);
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      expect(controller.isConnected, isFalse);
      expect(vcontrold.sessions.single, isEmpty); // nothing was sent blindly

      final probe = await ViessmannController.testConnection(config(timeoutSeconds: 1));
      expect(probe['success'], isFalse);
    });

    test('nothing listening on the port throws', () async {
      final port = vcontrold.port;
      await vcontrold.stop();
      final controller = ViessmannController(config: config(timeoutSeconds: 1));
      await expectLater(controller.connect(host: '127.0.0.1', port: port), throwsModbusError);
      // tearDown stops again; closing a closed server is fine.
    });

    test('testConnection reads values without a prior connect', () async {
      final result = await ViessmannController.testConnection(config());
      expect(result['success'], isTrue);
      expect(result['outdoorTemp'], 4.8);
      expect(result['flowTemp'], 47.5);
      expect(result['returnTemp'], 39.0);
      expect(result['hotWaterTemp'], 54.2);
      expect(result['roomTarget'], 20.0);
    });
  });

  group('ViCare cloud API v2', () {
    late MockVicareApi api;

    setUp(() async {
      api = MockVicareApi();
      await api.start();
    });

    tearDown(() => api.stop());

    ViessmannController controllerWith({String token = MockVicareApi.token}) => ViessmannController(
          vicareBaseUrl: api.baseUrl,
          config: ViessmannConfig(
            connectionType: ViessmannConnectionType.vicareRest,
            apiToken: token,
            circuit: '0',
            timeoutSeconds: 2,
          ),
        );

    test('resolves installation → gateway → heating device and reads the feature list', () async {
      final controller = controllerWith();
      expect(controller.protocol, ConnectionProtocol.restApi);
      await controller.connect(host: 'ignored.invalid');
      expect(controller.isConnected, isTrue);

      final telemetry = await controller.readTelemetry();
      expect(telemetry.outdoorTemp, 4.8);
      expect(telemetry.flowTemp, 47.5);
      expect(telemetry.returnTemp, 39.0);
      expect(telemetry.hotWaterTemp, 54.2);
      expect(telemetry.roomTarget, 21.0);
      expect(telemetry.heatingCurveShift, 2.0);

      // The heating device "0" was picked, not the vitoconnect "gateway".
      expect(api.requests, [
        'GET /equipment/installations?includeGateways=true',
        'GET /features/installations/123/gateways/7571381573112225/devices/0/features/',
      ]);
      await controller.disconnect();
    });

    test('a second readTelemetry within the cache time does not hit the API', () async {
      final controller = controllerWith();
      await controller.connect(host: 'ignored.invalid');
      final first = await controller.readTelemetry();
      final second = await controller.readTelemetry();
      await controller.readTelemetry();

      expect(second.outdoorTemp, first.outdoorTemp);
      expect(api.count('/features/'), 1);
      expect(api.count('/equipment/installations'), 1);
      await controller.disconnect();
    });

    test('setCurve sends the new shift as integer together with the unchanged slope', () async {
      final controller = controllerWith();
      await controller.connect(host: 'ignored.invalid');

      await controller.setHeatingCurveShift(5.0);
      expect(api.commandBodies['setCurve'], {'shift': 5, 'slope': 1.4});
      expect(api.commandBodies['setCurve']['shift'], isA<int>());
      expect(api.slope, 1.4);
      expect(
        api.requests.last,
        'POST /features/installations/123/gateways/7571381573112225/devices/0'
        '/features/heating.circuits.0.heating.curve/commands/setCurve',
      );

      // The read after the write must come from the API, not from the cache.
      expect((await controller.readTelemetry()).heatingCurveShift, 5.0);
      expect(api.count('GET /features/'), 2);
      await controller.disconnect();
    });

    test('setTemperature sends targetTemperature', () async {
      final controller = controllerWith();
      await controller.connect(host: 'ignored.invalid');

      await controller.setRoomTarget(22.5);
      expect(api.commandBodies['setTemperature'], {'targetTemperature': 22.5});
      expect(
        api.requests.last,
        'POST /features/installations/123/gateways/7571381573112225/devices/0'
        '/features/heating.circuits.0.operating.programs.normal/commands/setTemperature',
      );
      expect((await controller.readTelemetry()).roomTarget, 22.5);
      await controller.disconnect();
    });

    test('401 (expired token) throws an error that mentions the token', () async {
      final tokenError = throwsA(
        isA<ModbusCommunicationException>().having((e) => e.message, 'message', contains('Token')),
      );

      final expired = controllerWith(token: 'expired-token');
      await expectLater(expired.connect(host: 'ignored.invalid'), tokenError);
      expect(expired.isConnected, isFalse);

      // Token expires while connected: reads after the cache and writes fail the same way.
      final controller = controllerWith();
      await controller.connect(host: 'ignored.invalid');
      api.failWith = 401;
      await expectLater(controller.setRoomTarget(22.0), tokenError);
      expect(api.roomTarget, 21.0);
    });

    test('429 (daily quota) throws', () async {
      api.failWith = 429;
      final controller = controllerWith();
      await expectLater(
        controller.connect(host: 'ignored.invalid'),
        throwsA(isA<ModbusCommunicationException>().having((e) => e.message, 'message', contains('1450'))),
      );
      expect(controller.isConnected, isFalse);
    });
  });
}
