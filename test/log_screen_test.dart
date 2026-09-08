import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/log_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  Widget buildLogScreen(ECLProvider provider) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: ChangeNotifierProvider<ECLProvider>.value(
        value: provider,
        child: const LogScreen(),
      ),
    );
  }

  group('LogScreen Widget Tests', () {
    late ECLProvider provider;
    late ActivityLogService logService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      logService = ActivityLogService(enablePersistence: false);
      provider = ECLProvider(
        logService: logService,
        autoLoadDatabase: false,
      );

      // Seed mock log events
      await logService.logRead(
        controllerId: 'danfoss_ecl_310',
        action: 'READ_TELEMETRY',
        message: 'Telemetrie aktualisiert: VL 46.0°C, RL 36.0°C',
        details: {'flow': 46.0, 'return': 36.0},
      );

      await logService.logWrite(
        controllerId: 'danfoss_ecl_310',
        action: 'WRITE_SUCCESS',
        message: 'Sollwert erfolgreich auf 21.5 °C gesetzt',
        details: {'target': 21.5},
        success: true,
      );

      await logService.logRead(
        controllerId: 'danfoss_ecl_310',
        action: 'SENSOR_FAULT_DETECTED',
        message: 'Sensorfehler 19200 an S3 (Rücklauftemperatur)',
        details: {'param': 'return_temp', 'code': 19200},
        errorCode: 'SENSOR_FAULT_19200',
        level: ActivityLogLevel.warning,
      );

      await logService.logError(
        controllerId: 'danfoss_ecl_310',
        action: 'MODBUS_TIMEOUT',
        message: 'Zeitüberschreitung bei Registerabfrage 10200',
        category: ActivityLogCategory.controllerRead,
        errorCode: 'TIMEOUT_ERROR',
      );
    });

    testWidgets('renders KPI summary banner and initial log list', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildLogScreen(provider));
      await tester.pumpAndSettle();

      // Title
      expect(find.text('Aktivitäts- & Diagnoseprotokoll'), findsOneWidget);

      // KPI items
      expect(find.text('Gesamt'), findsOneWidget);
      expect(find.text('4'), findsWidgets); // Total = 4
      expect(find.text('Fehler'), findsWidgets);
      expect(find.text('Schreibbefehle'), findsWidgets);
      expect(find.text('Messungen'), findsOneWidget);

      // Log messages in list
      expect(find.text('Telemetrie aktualisiert: VL 46.0°C, RL 36.0°C'), findsOneWidget);
      expect(find.text('Sollwert erfolgreich auf 21.5 °C gesetzt'), findsOneWidget);
      expect(find.text('Sensorfehler 19200 an S3 (Rücklauftemperatur)'), findsOneWidget);
      expect(find.text('Zeitüberschreitung bei Registerabfrage 10200'), findsOneWidget);

      // Error code pill badge
      expect(find.text('Fehlercode: SENSOR_FAULT_19200'), findsOneWidget);
    });

    testWidgets('filters logs by search query and filter chips', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildLogScreen(provider));
      await tester.pumpAndSettle();

      // Search by error code 19200
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '19200');
      await tester.pumpAndSettle();

      // Only the 19200 entry should be visible
      expect(find.text('Sensorfehler 19200 an S3 (Rücklauftemperatur)'), findsOneWidget);
      expect(find.text('Sollwert erfolgreich auf 21.5 °C gesetzt'), findsNothing);

      // Clear search
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      // Tap 'Schreibbefehle' filter chip
      await tester.tap(find.widgetWithText(FilterChip, 'Schreibbefehle'));
      await tester.pumpAndSettle();

      expect(find.text('Sollwert erfolgreich auf 21.5 °C gesetzt'), findsOneWidget);
      expect(find.text('Telemetrie aktualisiert: VL 46.0°C, RL 36.0°C'), findsNothing);
    });

    testWidgets('expands technical JSON details on tap', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildLogScreen(provider));
      await tester.pumpAndSettle();

      // Tap card with 19200
      await tester.tap(find.text('Sensorfehler 19200 an S3 (Rücklauftemperatur)'));
      await tester.pumpAndSettle();

      // Expanded action and details
      expect(find.text('Aktion: SENSOR_FAULT_DETECTED'), findsOneWidget);
      expect(find.textContaining('"code": 19200'), findsOneWidget);
    });

    testWidgets('opens backoffice consent sheet and enables export after confirmation',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildLogScreen(provider));
      await tester.pumpAndSettle();

      // Tap Cloud upload icon in AppBar
      await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
      await tester.pumpAndSettle();

      // Modal bottom sheet visible
      expect(find.text('Diagnose & Fehlerbericht'), findsOneWidget);

      final checkboxFinder = find.byType(CheckboxListTile);
      final exportBtnFinder = find.ancestor(
        of: find.text('Diagnosebericht bestätigen & exportieren'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );

      // Confirm button is initially disabled
      expect(tester.widget<FilledButton>(exportBtnFinder).enabled, isFalse);

      // Check acknowledgment checkbox
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Confirm button is now enabled
      expect(tester.widget<FilledButton>(exportBtnFinder).enabled, isTrue);

      // Tap export button
      await tester.tap(exportBtnFinder);
      await tester.pumpAndSettle();

      // Bottom sheet closed and snackbar shown
      expect(find.text('Diagnosebericht erfolgreich bestätigt und exportiert.'), findsOneWidget);
    });
  });
}
