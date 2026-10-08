import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/screens/holiday_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/device_registry.dart';
import 'package:heizungstrainer/services/holiday_service.dart';
import 'package:heizungstrainer/services/license_service.dart';

/// A non-Danfoss controller as the provider sees it: telemetry + writes for
/// shift and/or room target, nothing else.
class _Driver implements HeatingController {
  _Driver(this.id, {required this.shift, required this.room});
  @override
  final String id;
  double? shift;
  double? room;
  final writes = <String>[];

  @override
  String get brandName => id;
  @override
  String get modelName => 'Matrix';
  @override
  ConnectionProtocol get protocol => ConnectionProtocol.modbusTcp;
  @override
  HeatingCapabilities get capabilities =>
      HeatingCapabilities(supportsHeatingCurveShift: shift != null, supportsRoomTarget: room != null);
  @override
  bool get isConnected => true;
  @override
  Stream<ControllerTelemetry> get telemetryStream => const Stream.empty();
  @override
  Future<void> connect({required String host, int? port, Map<String, dynamic>? extraConfig}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<ControllerTelemetry> readTelemetry() async => ControllerTelemetry(
        timestamp: DateTime.now(),
        outdoorTemp: 4,
        flowTemp: 38,
        returnTemp: 31,
        hotWaterTemp: 49,
        heatingCurveShift: shift,
        roomTarget: room,
      );
  @override
  Future<void> setHeatingCurveShift(double v) async {
    writes.add('shift=$v');
    shift = v;
  }

  @override
  Future<void> setRoomTarget(double v) async {
    writes.add('room=$v');
    room = v;
  }
}

Future<(ECLProvider, _Driver, ActivityLogService)> connect(String id, {bool shift = true}) async {
  final log = ActivityLogService(enablePersistence: false, enableRemoteDispatch: false);
  final provider = ECLProvider(
    logService: log,
    licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
    autoLoadDatabase: false,
  );
  await provider.setSelectedController(id);
  final driver = _Driver(id, shift: shift ? 0 : null, room: 21);
  provider.useControllerForTesting(driver);
  provider.setConnectedForTesting(ip: '192.168.178.60');
  if (provider.isBetaController) await provider.setBetaWritesEnabled(true);
  await provider.refreshReadings();
  return (provider, driver, log);
}

void main() {
  final others = [for (final d in DeviceRegistry.knownControllers) if (d.id != 'danfoss_ecl_310') d.id];

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('matrix covers all 6 non-Danfoss drivers', () => expect(others, hasLength(6)));

  for (final id in others) {
    group(id, () {
      test('Danfoss-only features stay off and their writes are refused', () async {
        final (p, driver, _) = await connect(id);
        expect(p.supportsControllerSchedule, isFalse);
        expect(p.supportsDhwSettings, isFalse);
        expect(p.supportsControllerHoliday, isFalse);
        expect(p.supportsLiveView, isFalse);
        for (final param in [
          ECLRegisters.savingRoomTemp,
          ECLRegisters.curveMaxFlow,
          ECLRegisters.dhwComfortSetpoint,
          ECLRegisters.antiBacteriaTemp,
        ]) {
          await expectLater(p.writeParameter(param, param.minValue ?? 40), throwsA(isA<Exception>()), reason: param.id);
        }
        expect(driver.writes, isEmpty);
        expect(await p.readControllerHolidays(), isEmpty);
        await expectLater(p.writeScheduleDay(0, const []), throwsA(isA<ModbusCommunicationException>()));
      });

      test('room setpoint write goes to the driver, is confirmed and logged before → after', () async {
        final (p, driver, log) = await connect(id);
        await p.writeParameter(ECLRegisters.roomTargetTemp, 20);
        expect(driver.writes, ['room=20.0']);
        final w = log.recentEntries.firstWhere((e) => e.action == 'WRITE_PARAMETER_VERIFIED');
        expect(w.message, contains('21 → 20'));
      });

      test('change at the controller is detected as "outside the app"', () async {
        final (p, driver, log) = await connect(id);
        driver.room = 23;
        await p.refreshReadings();
        expect(log.recentEntries.where((e) => e.action == 'SETTING_CHANGED_OUTSIDE_APP'), hasLength(1));
        expect(p.alerts.alerts.single.title, 'Außerhalb der App geändert');
      });

      test('holiday runs app-side (shift if available, else room) and restores', () async {
        for (final withShift in [true, false]) {
          final (p, driver, _) = await connect(id, shift: withShift);
          final service = HolidayService(inMemoryStorage: {});
          final now = DateTime(2026, 10, 10, 12);
          final plan = await service.activatePlan(
            plan: HolidayPlan(id: 'h', title: 'Test', startDateTime: now, endDateTime: now.add(const Duration(days: 3)), createdAt: now),
            provider: p,
            now: now,
          );
          expect(plan.runsInController, isFalse);
          expect(plan.controlMode, withShift ? 'shift' : 'room');
          expect(driver.writes, isNotEmpty);
          await service.cancelOrFinishPlan(plan: plan, provider: p);
          expect(withShift ? driver.shift : driver.room, withShift ? 0 : 21);
        }
      });

      testWidgets('home and holiday screens build without errors', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.6;
        addTearDown(tester.view.resetPhysicalSize);
        final (p, _, _) = (await tester.runAsync(() => connect(id)))!;
        for (final screen in const [HomeScreen(), HolidayScreen()]) {
          await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
            value: p,
            child: MaterialApp(home: Scaffold(body: screen)),
          ));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: '$id ${screen.runtimeType}');
        }
        expect(find.byKey(const Key('openConfigCheck')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    });
  }

  test('log levels: the external change is a warning, not an error', () {
    expect(ActivityLogLevel.warning.index, lessThan(ActivityLogLevel.error.index));
  });
}
