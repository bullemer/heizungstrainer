import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/models/controller_holiday.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/dhw_settings_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/config_check.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/services/holiday_service.dart';
import 'package:heizungstrainer/services/license_service.dart';

ActivityLogService quietLog() => ActivityLogService(enablePersistence: false, enableRemoteDispatch: false);

/// Room-only driver whose readTelemetry can be held open (to overlap a write).
class _SlowDriver implements HeatingController {
  double room = 21;
  Completer<void>? gate;
  @override
  String get id => 'nibe_modbus';
  @override
  String get brandName => 'Test';
  @override
  String get modelName => 'Slow';
  @override
  ConnectionProtocol get protocol => ConnectionProtocol.modbusTcp;
  @override
  HeatingCapabilities get capabilities => const HeatingCapabilities(supportsHeatingCurveShift: false);
  @override
  bool get isConnected => true;
  @override
  Stream<ControllerTelemetry> get telemetryStream => const Stream.empty();
  @override
  Future<void> connect({required String host, int? port, Map<String, dynamic>? extraConfig}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<ControllerTelemetry> readTelemetry() async {
    final snapshot = room; // value at the start of the poll
    if (gate != null) await gate!.future;
    return ControllerTelemetry(timestamp: DateTime.now(), flowTemp: 30, roomTarget: snapshot);
  }

  @override
  Future<void> setHeatingCurveShift(double shift) async {}
  @override
  Future<void> setRoomTarget(double t) async => room = t;
}

class _NoHolidayYet extends ECLProvider {
  _NoHolidayYet() : super(logService: quietLog(), autoLoadDatabase: false);
  @override
  bool get isConnected => true;
  @override
  bool get supportsControllerHoliday => false; // application not read yet
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('#1 a controller holiday is not dropped while the slot layout is still unknown', () async {
    final provider = _NoHolidayYet();
    final service = HolidayService(inMemoryStorage: {});
    final now = DateTime(2026, 10, 9);
    await service.savePlan(HolidayPlan(
      id: 'w', title: 'Wochenend-Trip', startDateTime: now, endDateTime: now.add(const Duration(days: 2)),
      isActive: true, setbackApplied: true, controlMode: 'controller', controllerSlot: 3, createdAt: now));
    expect(await service.runDueActions(provider: provider, now: now.add(const Duration(hours: 3))), isNull);
    expect((await service.getActivePlan())?.id, 'w');
    expect(provider.alerts.alerts, isEmpty);
  });

  test('#2 max flow reached by the curve → fix is "lower the curve", not the limit', () {
    final f = runConfigCheck(const ConfigCheckInput(
      comfort: 21,
      curve: ControllerHeatingCurve(outdoorTemps: [-30, -15, -5, 0, 5, 15], flowTemps: [58, 50, 44, 40, 35, 25], slope: 0.5),
      reference: BuildingReference.floorAfter2010,
      maxFlow: 50,
    )).firstWhere((x) => x.id == 'max_flow_floor');
    expect(f.severity, FindingSeverity.warning);
    expect(f.action, FindingAction.openCurveAssistant);
  });

  test('#3 a poll overlapping a write is discarded – no false "app change missing"', () async {
    final log = quietLog();
    final driver = _SlowDriver();
    final p = ECLProvider(
        logService: log, licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro), autoLoadDatabase: false);
    await p.setSelectedController('nibe_modbus');
    p.useControllerForTesting(driver);
    p.setConnectedForTesting(ip: '192.168.0.9');
    await p.setBetaWritesEnabled(true);
    await p.refreshReadings(); // baseline 21

    driver.gate = Completer<void>();
    final poll = p.refreshReadings(); // reads 21, held open
    await Future<void>.delayed(Duration.zero);
    final gate = driver.gate!;
    driver.gate = null; // the write's own read-back is not held
    await p.writeParameter(ECLRegisters.roomTargetTemp, 22);
    gate.complete();
    await poll;

    expect(log.recentEntries.where((e) => e.action == 'APP_CHANGE_NOT_ON_DEVICE'), isEmpty);
    expect(p.getReading(ECLRegisters.roomTargetTemp)!.displayValue, 22);
    p.dispose();
  });

  test('#6 switching controller clears the previous controller\'s schedule', () async {
    final p = ECLProvider(logService: quietLog(), autoLoadDatabase: false);
    p.setControllerScheduleForTesting(WeekSchedule([for (var d = 0; d < 7; d++) [SchedulePeriod.allDay, SchedulePeriod.unused, SchedulePeriod.unused]]));
    await p.setSelectedController('vaillant_ebusd');
    expect(p.controllerSchedule, isNull);
    p.dispose();
  });

  test('#9 one-day holiday on the spring DST day is accepted', () {
    final d = ControllerHolidayLayout.datesFor(start: DateTime(2026, 3, 29, 8), heatUpFrom: DateTime(2026, 3, 30, 15));
    expect(d, isNotNull);
    expect(d!.end, DateTime(2026, 3, 30));
  });

  testWidgets('#10 hot-water saving picker opens even if comfort is below 40 °C', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    final p = _DhwProvider()
      ..setReadingForTesting(ECLRegisters.dhwComfortSetpoint, 38)
      ..setReadingForTesting(ECLRegisters.dhwSavingSetpoint, 36);
    await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(value: p, child: const MaterialApp(home: DhwSettingsScreen())));
    await tester.pump();
    await tester.tap(find.text('Spar').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Warmwasser Spar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    p.dispose();
  });
}

class _DhwProvider extends ECLProvider {
  _DhwProvider() : super(logService: quietLog(), autoLoadDatabase: false);
  @override
  bool get supportsDhwSettings => true;
}
