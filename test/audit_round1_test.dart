import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/license_exception.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/screens/live_view_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/holiday_service.dart';
import 'package:heizungstrainer/services/license_service.dart';

ECLProvider _provider() => ECLProvider(
      logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
      licenseService: LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro),
      autoLoadDatabase: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('user-facing errors never show class names', () {
    expect(
      userFacingError(const LicenseRequiredException(message: 'Pro nötig.')),
      'Pro nötig.',
    );
    expect(userFacingError(Exception('kaputt')), 'kaputt');
    expect(userFacingError(const FormatException('falsch')), 'falsch');
  });

  test('"Kein Messdienstleister": nothing to sync, no example data', () async {
    final provider = _provider();
    await provider.setSelectedBillingProvider('none');
    expect(provider.hasBillingProvider, isFalse);
    await provider.syncBillingData();
    expect(provider.brunataData, isNull);
    expect(provider.brunataSyncError, isNull);
    expect(provider.isExampleBillingData, isFalse);
    provider.dispose();
  });

  test('a plan made on the real controller is never restored in demo mode', () async {
    final service = HolidayService(inMemoryStorage: {});
    final now = DateTime(2026, 11, 1, 12);
    await service.savePlan(HolidayPlan(
      id: 'real',
      title: 'Echt',
      startDateTime: now.subtract(const Duration(days: 2)),
      endDateTime: now.subtract(const Duration(hours: 1)),
      setbackApplied: true,
      createdAt: now.subtract(const Duration(days: 3)),
    ));
    final demo = _provider();
    await demo.startSimulation();
    expect(await service.runDueActions(provider: demo, now: now), isNull);
    expect((await service.getActivePlan())!.isActive, isTrue); // still open for the real controller
    demo.dispose();
  });

  testWidgets('home banner: no value is not a broken sensor; frost mode is named', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = _provider()..setConnectedForTesting(ip: '192.168.0.2');
    Future<void> pump() => tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
          value: provider,
          child: const MaterialApp(home: HomeScreen()),
        ));
    await pump();
    expect(find.text('Außentemperatur: noch kein Wert'), findsOneWidget);
    expect(find.textContaining('Fühlerabriss'), findsNothing);

    provider
      ..setReadingForTesting(ECLRegisters.outdoorTemp, 5)
      ..setReadingForTesting(ECLRegisters.summerCutoff, 13)
      ..setReadingForTesting(ECLRegisters.circuitMode, 4);
    await pump();
    expect(find.textContaining('Frostschutz'), findsWidgets);
    expect(find.textContaining('Heizbetrieb aktiv'), findsNothing);

    provider.setReadingForTesting(ECLRegisters.circuitMode, 1);
    await pump();
    expect(find.text('5.0 °C draußen — Heizbetrieb'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('Live tab explains that other brands have no plant diagram', (tester) async {
    final provider = _provider();
    await provider.setSelectedController('nibe_modbus');
    provider.setConnectedForTesting(ip: '192.168.0.3');
    await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
      value: provider,
      child: const MaterialApp(home: LiveViewScreen(refreshInterval: Duration(hours: 1))),
    ));
    await tester.pump();
    expect(find.byKey(const Key('liveUnsupported')), findsOneWidget);
    expect(find.textContaining('nur für den Danfoss ECL 310'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
