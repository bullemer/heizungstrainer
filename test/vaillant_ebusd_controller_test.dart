import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';
import 'package:heizungstrainer/controllers/vaillant_ebusd_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';

class _AllowLocalHttpOverrides extends HttpOverrides {}

/// Imitates an ebusd daemon with both of its ports:
/// - HTTP JSON port (`--httpport`): `GET /data` lists all messages,
///   `GET /data/CIRCUIT/NAME` one of them; anything but GET → 405.
/// - TCP command port: `write -c CIRCUIT NAME VALUE` answers `done` or
///   `ERR: …`, each followed by an empty line. The connection stays open.
class MockEbusd {
  /// circuit → message name → `fields` object (null = never read from the bus).
  final Map<String, Map<String, Map<String, dynamic>?>> circuits = {
    'bai': {
      'FlowTemp': {
        'temp': {'value': 48.5},
        'sensor': {'value': 'ok'},
      },
      'ReturnTemp': {
        'temp': {'value': 37.2},
        'tempmirror': {'value': 65228},
        'sensor': {'value': 'ok'},
      },
      'OutdoorstempSensor': {
        'temp2': {'value': 6.8},
        'sensor': {'value': 'ok'},
      },
      'StorageTemp': {
        'temp': {'value': 53.0},
        'sensor': {'value': 'ok'},
      },
    },
    '700': {
      'Z1DayTemp': {
        'tempv': {'value': 21.0},
      },
    },
  };

  /// Request URIs (path + query) of all GETs on the HTTP port.
  final List<String> httpGets = [];

  /// Methods of all non-GET requests on the HTTP port (each got a 405).
  final List<String> rejectedMethods = [];

  /// Lines received on the command port.
  final List<String> commands = [];

  /// Circuits whose regulator refuses writes on the bus.
  bool writesFail = false;

  late final HttpServer _http;
  late final ServerSocket _command;
  final List<Socket> _sockets = [];

  int get httpPort => _http.port;
  int get commandPort => _command.port;

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen(_serveHttp);
    _command = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _command.listen(_serveCommand);
  }

  bool _stopped = false;

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final s in _sockets) {
      s.destroy();
    }
    await _command.close();
    await _http.close(force: true);
  }

  Map<String, dynamic> _message(String name, Map<String, dynamic>? fields) => {
        'name': name,
        'passive': false,
        'write': false,
        // A unix timestamp – must never be taken for a temperature.
        'lastup': fields == null ? 0 : 1700000000,
        'zz': 8,
        'fields': ?fields,
      };

  static const _global = {'version': '23.2', 'signal': true, 'lastup': 1700000001};

  Future<void> _serveHttp(HttpRequest request) async {
    await request.drain<void>();
    if (request.method != 'GET') {
      rejectedMethods.add(request.method);
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    httpGets.add(request.uri.toString());

    final segments = request.uri.pathSegments;
    Map<String, dynamic>? body;
    if (segments.length == 1 && segments[0] == 'data') {
      body = {
        for (final c in circuits.entries)
          c.key: {
            'messages': {for (final m in c.value.entries) m.key: _message(m.key, m.value)},
          },
        'global': _global,
      };
    } else if (segments.length == 3 && segments[0] == 'data') {
      final circuit = segments[1];
      final name = segments[2];
      final known = circuits[circuit]?.containsKey(name) ?? false;
      body = {
        if (known)
          circuit: {
            'messages': {name: _message(name, circuits[circuit]![name])},
          },
        'global': _global,
      };
    }

    if (body == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
    }
    await request.response.close();
  }

  String _execute(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 5 || parts[0] != 'write' || parts[1] != '-c') {
      return 'ERR: command not found';
    }
    final fields = circuits[parts[2]]?[parts[3]];
    final value = double.tryParse(parts[4]);
    if (fields == null || writesFail) return 'ERR: element not found';
    if (value == null) return 'ERR: invalid numeric argument';
    (fields.values.first as Map<String, dynamic>)['value'] = value;
    return 'done';
  }

  void _serveCommand(Socket socket) {
    _sockets.add(socket);
    socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        commands.add(line);
        socket.write('${_execute(line)}\n\n');
      },
      onError: (Object _) {},
      cancelOnError: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowLocalHttpOverrides();

  final throwsModbusError = throwsA(isA<ModbusCommunicationException>());

  group('VaillantEbusdConfig & Presets Tests', () {
    test('contains expected factory presets', () {
      final presets = VaillantEbusdConfig.presets;
      expect(
        presets.map((p) => p.id),
        ['ebusd_http_json', 'ebusd_sensocomfort', 'ebusd_multimatic', 'ebusd_calormatic', 'custom'],
      );
    });

    test('presets use the circuit names of ebusd (VRC 720 = ctlv2)', () {
      String circuitOf(String id) => VaillantEbusdConfig.presets.firstWhere((p) => p.id == id).defaultCircuit;
      expect(circuitOf('ebusd_http_json'), 'bai');
      expect(circuitOf('ebusd_sensocomfort'), 'ctlv2');
      expect(circuitOf('ebusd_multimatic'), '700');
      expect(circuitOf('ebusd_calormatic'), '470');
    });

    test('default config values are valid', () {
      const config = VaillantEbusdConfig();
      expect(config.host, '192.168.1.140');
      expect(config.port, 8889);
      expect(config.commandPort, 8888);
      expect(config.circuit, 'bai');
      expect(config.useHttps, isFalse);
      expect(config.apiToken, isEmpty);
      expect(config.presetId, 'ebusd_http_json');
      expect(config.baseUrl, 'http://192.168.1.140:8889');
      expect(config.getUri('/data').path, '/data');
    });

    test('toJson and fromJson preserves all fields', () {
      const original = VaillantEbusdConfig(
        host: '10.0.0.145',
        port: 8080,
        commandPort: 9999,
        circuit: '700',
        apiToken: 'proxy_token_xyz',
        useHttps: true,
        timeoutSeconds: 8,
        presetId: 'ebusd_multimatic',
        presetName: 'Vaillant multiMATIC (VRC 700)',
      );

      final restored = VaillantEbusdConfig.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
    });

    test('stored circuit "720" loads as "ctlv2"; configs without commandPort get 8888', () {
      final restored = VaillantEbusdConfig.fromJson({
        'host': '10.0.0.145',
        'port': 8889,
        'circuit': '720',
        'presetId': 'ebusd_sensocomfort',
      });
      expect(restored.circuit, 'ctlv2');
      expect(restored.commandPort, 8888);
      expect(restored.host, '10.0.0.145');
      expect(VaillantEbusdConfig.fromJson({'circuit': '700'}).circuit, '700');
    });

    test('secure storage save and load cycle (legacy circuit 720 is migrated)', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      final initial = await VaillantEbusdConfig.load(storage);
      expect(initial.presetId, 'ebusd_http_json');

      final custom = initial.copyWith(
        presetId: 'custom',
        host: '192.168.178.99',
        circuit: '720',
        commandPort: 18888,
      );
      await custom.save(storage);

      final loaded = await VaillantEbusdConfig.load(storage);
      expect(loaded.presetId, 'custom');
      expect(loaded.host, '192.168.178.99');
      expect(loaded.circuit, 'ctlv2');
      expect(loaded.commandPort, 18888);
    });
  });

  group('ebusd fields parsing', () {
    test('takes the temperature field, never the sensor status', () {
      expect(
        VaillantEbusdController.fieldValue({
          'temp': {'value': 48.5},
          'sensor': {'value': 'ok'},
        }),
        48.5,
      );
      expect(
        VaillantEbusdController.fieldValue({
          'tempv': {'value': 21.0},
        }),
        21.0,
      );
    });

    test('a sensor that is not "ok" (cutoff, circuit) yields null', () {
      for (final status in ['cutoff', 'circuit']) {
        expect(
          VaillantEbusdController.fieldValue({
            'temp': {'value': -50.0},
            'sensor': {'value': status},
          }),
          isNull,
          reason: status,
        );
      }
    });

    test('no fields (message never read) yields null', () {
      expect(VaillantEbusdController.fieldValue(null), isNull);
      expect(VaillantEbusdController.fieldValue(<String, dynamic>{}), isNull);
      expect(
        VaillantEbusdController.fieldValue({
          'temp': {'value': null},
        }),
        isNull,
      );
    });
  });

  group('VaillantEbusdController against a mock ebusd', () {
    late MockEbusd ebusd;

    setUp(() async {
      ebusd = MockEbusd();
      await ebusd.start();
    });

    tearDown(() => ebusd.stop());

    VaillantEbusdConfig config({String circuit = '700'}) => VaillantEbusdConfig(
          host: '127.0.0.1',
          port: ebusd.httpPort,
          commandPort: ebusd.commandPort,
          circuit: circuit,
          timeoutSeconds: 2,
        );

    Future<VaillantEbusdController> connect({String circuit = '700'}) async {
      final controller = VaillantEbusdController(config: config(circuit: circuit));
      await controller.connect(host: '127.0.0.1', port: ebusd.httpPort);
      expect(controller.isConnected, isTrue);
      return controller;
    }

    test('capabilities: no curve shift; room setpoint only with a regulator circuit', () async {
      final boilerOnly = VaillantEbusdController();
      expect(boilerOnly.id, 'vaillant_ebusd');
      expect(boilerOnly.brandName, 'Vaillant');
      expect(boilerOnly.modelName, contains('eBUS'));
      expect(boilerOnly.isConnected, isFalse);
      expect(boilerOnly.protocol, ConnectionProtocol.restApi);
      expect(boilerOnly.config.circuit, 'bai');
      expect(boilerOnly.capabilities.supportsHeatingCurveShift, isFalse);
      expect(boilerOnly.capabilities.supportsRoomTarget, isFalse);
      expect(boilerOnly.capabilities.supportsHotWater, isTrue);
      expect(boilerOnly.capabilities.supportsReturnTemp, isTrue);
      expect(boilerOnly.capabilities.supportsOutdoorTemp, isTrue);

      for (final circuit in ['700', 'ctlv2', '470']) {
        final regulator = VaillantEbusdController(config: VaillantEbusdConfig(circuit: circuit));
        expect(regulator.capabilities.supportsRoomTarget, isTrue, reason: circuit);
        expect(regulator.capabilities.supportsHeatingCurveShift, isFalse, reason: circuit);
      }
    });

    test('reads boiler sensors and the regulator setpoint from the real JSON shape', () async {
      final controller = await connect();
      ebusd.httpGets.clear();

      final telemetry = await controller.readTelemetry();
      expect(telemetry.flowTemp, 48.5);
      expect(telemetry.returnTemp, 37.2);
      expect(telemetry.outdoorTemp, 6.8);
      expect(telemetry.hotWaterTemp, 53.0);
      expect(telemetry.roomTarget, 21.0);
      expect(telemetry.heatingCurveShift, isNull);
      expect(telemetry.spread, closeTo(11.3, 0.01));

      // Single values are requested with maxage so ebusd refreshes them from the bus.
      expect(ebusd.httpGets.toSet(), {
        '/data/bai/OutdoorstempSensor?maxage=60',
        '/data/bai/FlowTemp?maxage=60',
        '/data/bai/ReturnTemp?maxage=60',
        '/data/bai/StorageTemp?maxage=60',
        '/data/700/Z1DayTemp?maxage=60',
      });
      expect(ebusd.rejectedMethods, isEmpty);

      await controller.disconnect();
      expect(controller.isConnected, isFalse);
    });

    test('"lastup" is never mistaken for a temperature; unread messages are null', () async {
      // Known to ebusd but never read: "lastup": 0 and no "fields".
      ebusd.circuits['bai']!['StorageTemp'] = null;
      ebusd.circuits['bai']!['FlowTemp'] = null;

      final controller = await connect();
      final telemetry = await controller.readTelemetry();
      expect(telemetry.hotWaterTemp, isNull);
      expect(telemetry.flowTemp, isNull);
      expect(telemetry.returnTemp, 37.2);
      expect(telemetry.outdoorTemp, 6.8);
      for (final value in telemetry.rawValues.values) {
        expect(value, lessThan(100));
      }
      await controller.disconnect();
    });

    test('a sensor reporting "cutoff" yields null instead of its bogus temperature', () async {
      ebusd.circuits['bai']!['ReturnTemp'] = {
        'temp': {'value': -50.0},
        'tempmirror': {'value': 65228},
        'sensor': {'value': 'cutoff'},
      };
      final controller = await connect();
      final telemetry = await controller.readTelemetry();
      expect(telemetry.returnTemp, isNull);
      expect(telemetry.flowTemp, 48.5);
      await controller.disconnect();
    });

    test('message names are used exactly as ebusd spells them (z1DayTemp)', () async {
      // Older ebusd Vaillant configurations spell it with a lower-case z.
      ebusd.circuits['700'] = {
        'z1DayTemp': {
          'tempv': {'value': 19.5},
        },
      };
      final controller = await connect();
      expect((await controller.readTelemetry()).roomTarget, 19.5);
      expect(ebusd.httpGets, contains('/data/700/z1DayTemp?maxage=60'));
      expect(ebusd.httpGets.where((u) => u.contains('Z1DayTemp')), isEmpty);

      await controller.setRoomTarget(20.5);
      expect(ebusd.commands, ['write -c 700 z1DayTemp 20.5']);
      await controller.disconnect();
    });

    test('calorMATIC 470 uses Hc1DayTemp', () async {
      ebusd.circuits.remove('700');
      ebusd.circuits['470'] = {
        'Hc1DayTemp': {
          'temp1': {'value': 20.0},
        },
      };
      final controller = await connect(circuit: '470');
      expect((await controller.readTelemetry()).roomTarget, 20.0);
      await controller.setRoomTarget(21.0);
      expect(ebusd.commands, ['write -c 470 Hc1DayTemp 21.0']);
      await controller.disconnect();
    });

    test('writes the room setpoint over the TCP command port, never over HTTP', () async {
      final controller = await connect();

      await controller.setRoomTarget(20.5);
      expect(ebusd.commands, ['write -c 700 Z1DayTemp 20.5']);
      expect(ebusd.rejectedMethods, isEmpty);
      expect(ebusd.httpGets.where((u) => u.contains('value=') || u.contains('20.5')), isEmpty);

      // Read back through the JSON port.
      expect((await controller.readTelemetry()).roomTarget, 20.5);
      await controller.disconnect();
    });

    test('a write answered with ERR throws', () async {
      final controller = await connect();
      ebusd.writesFail = true;

      await expectLater(
        controller.setRoomTarget(22.0),
        throwsA(isA<ModbusCommunicationException>()
            .having((e) => e.message, 'message', contains('ERR: element not found'))),
      );
      expect(ebusd.commands, hasLength(1));
      expect((await controller.readTelemetry()).roomTarget, 21.0);
      await controller.disconnect();
    });

    test('a closed command port throws and names the port', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = closed.port;
      await closed.close();
      final controller = VaillantEbusdController(config: config().copyWith(commandPort: deadPort));
      await controller.connect(host: '127.0.0.1', port: ebusd.httpPort);

      await expectLater(
        controller.setRoomTarget(22.0),
        throwsA(isA<ModbusCommunicationException>().having((e) => e.message, 'message', contains('$deadPort'))),
      );
      await controller.disconnect();
    });

    test('setHeatingCurveShift always throws and sends nothing', () async {
      final controller = await connect();
      await expectLater(controller.setHeatingCurveShift(2.0), throwsModbusError);
      expect(ebusd.commands, isEmpty);
      expect(ebusd.rejectedMethods, isEmpty);
      await controller.disconnect();
    });

    test('boiler-only config (bai) reads the sensors and refuses to write', () async {
      final controller = await connect(circuit: 'bai');
      final telemetry = await controller.readTelemetry();
      expect(telemetry.flowTemp, 48.5);
      expect(telemetry.roomTarget, isNull);
      expect(ebusd.httpGets.where((u) => u.startsWith('/data/700')), isEmpty);

      await expectLater(controller.setRoomTarget(21.0), throwsModbusError);
      expect(ebusd.commands, isEmpty);
      await controller.disconnect();
    });

    test('setRoomTarget without a connection throws', () async {
      final controller = VaillantEbusdController(config: config());
      await expectLater(controller.setRoomTarget(21.0), throwsModbusError);
      expect(ebusd.commands, isEmpty);
    });

    test('an ebusd without Vaillant circuits is rejected on connect', () async {
      ebusd.circuits
        ..clear()
        ..['broadcast'] = {
          'vdatetime': {
            'time': {'value': '12:00:00'},
          },
        };
      final controller = VaillantEbusdController(config: config());
      await expectLater(controller.connect(host: '127.0.0.1', port: ebusd.httpPort), throwsModbusError);
      expect(controller.isConnected, isFalse);
    });

    test('an HTTP server that is not ebusd is rejected on connect', () async {
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => other.close(force: true));
      other.listen((request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'ok'}));
        await request.response.close();
      });

      final controller = VaillantEbusdController(config: config());
      await expectLater(controller.connect(host: '127.0.0.1', port: other.port), throwsModbusError);
      expect(controller.isConnected, isFalse);
    });

    test('testConnection reads values without a prior connect', () async {
      final ok = await VaillantEbusdController.testConnection(config());
      expect(ok['success'], isTrue);
      expect(ok['flowTemp'], 48.5);
      expect(ok['roomTarget'], 21.0);

      final unreachable = config();
      await ebusd.stop();
      final failed = await VaillantEbusdController.testConnection(unreachable);
      expect(failed['success'], isFalse);
    });
  });
}
