import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/database_service.dart';
import 'package:heizungstrainer/screens/connection_screen.dart';
import 'package:heizungstrainer/widgets/analysis_section.dart';
import 'package:heizungstrainer/widgets/app_top_status_bar.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AppTopStatusBar Tests', () {
    late DatabaseService dbService;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService(preOpenedDb: db);
    });

    tearDown(() async {
      await dbService.close();
    });

    testWidgets('displays connected controller name and IP address with small font', (tester) async {
      final provider = ECLProvider(
        databaseService: dbService,
        autoLoadDatabase: false,
      );

      await provider.setSelectedController('viessmann_vicare');
      provider.setConnectedForTesting(ip: '192.168.1.55');

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ECLProvider>.value(
            value: provider,
            child: const Scaffold(
              body: AppTopStatusBar(),
            ),
          ),
        ),
      );

      final controllerTextFinder = find.byKey(const Key('controller_status_text'));
      expect(controllerTextFinder, findsOneWidget);

      final Text textWidget = tester.widget(controllerTextFinder);
      expect(textWidget.data, contains('Verbunden: Viessmann'));
      expect(textWidget.data, contains('192.168.1.55'));
      expect(textWidget.style?.fontSize, 11);

      provider.dispose();
    });

    testWidgets('shows neutral "Nicht verbunden" before any connection attempt', (tester) async {
      final provider = ECLProvider(
        databaseService: dbService,
        autoLoadDatabase: false,
      );

      // In initial state, controller is disconnected
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ECLProvider>.value(
            value: provider,
            child: const Scaffold(
              body: AppTopStatusBar(),
            ),
          ),
        ),
      );

      final controllerTextFinder = find.byKey(const Key('controller_status_text'));
      expect(controllerTextFinder, findsOneWidget);

      final Text textWidget = tester.widget(controllerTextFinder);
      expect(textWidget.data, contains('Nicht verbunden'));
      expect(textWidget.style?.fontSize, 11);

      // A real failure is shown as an error.
      provider.setConnectedForTesting(
        state: ECLConnectionState.error,
        errorMessage: 'Zeitüberschreitung',
      );
      await tester.pump();
      final Text errorText = tester.widget(controllerTextFinder);
      expect(errorText.data, contains('Verbindung nicht möglich: Zeitüberschreitung'));

      provider.dispose();
    });

    testWidgets('displays "Noch nie synchronisiert" when no billing sync occurred', (tester) async {
      final provider = ECLProvider(
        databaseService: dbService,
        autoLoadDatabase: false,
      );

      expect(provider.lastBillingSyncTime, isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ECLProvider>.value(
            value: provider,
            child: const Scaffold(
              body: AppTopStatusBar(),
            ),
          ),
        ),
      );

      final billingTextFinder = find.byKey(const Key('billing_status_text'));
      expect(billingTextFinder, findsOneWidget);

      final Text textWidget = tester.widget(billingTextFinder);
      expect(textWidget.data, contains('Noch nie synchronisiert'));
      expect(textWidget.style?.fontSize, 11);

      final billingIconFinder = find.byKey(const Key('billing_status_icon'));
      expect(billingIconFinder, findsOneWidget);
      final Icon iconWidget = tester.widget(billingIconFinder);
      expect(iconWidget.icon, Icons.warning_amber_rounded);

      provider.dispose();
    });

    testWidgets('displays last sync time when billing sync has occurred', (tester) async {
      final provider = ECLProvider(
        databaseService: dbService,
        autoLoadDatabase: false,
      );

      final syncTime = DateTime.now();
      provider.setLastBillingSyncTime(syncTime);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ECLProvider>.value(
            value: provider,
            child: const Scaffold(
              body: AppTopStatusBar(),
            ),
          ),
        ),
      );

      final billingTextFinder = find.byKey(const Key('billing_status_text'));
      expect(billingTextFinder, findsOneWidget);

      final Text textWidget = tester.widget(billingTextFinder);
      expect(textWidget.data, contains('Letzter Sync'));
      expect(textWidget.data, contains('Heute'));
      expect(textWidget.style?.fontSize, 11);

      final billingIconFinder = find.byKey(const Key('billing_status_icon'));
      expect(billingIconFinder, findsOneWidget);
      final Icon iconWidget = tester.widget(billingIconFinder);
      expect(iconWidget.icon, Icons.cloud_done_outlined);

      provider.dispose();
    });

    testWidgets('AppTopStatusBar contains Settings button', (tester) async {
      final provider = ECLProvider(
        databaseService: dbService,
        autoLoadDatabase: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ECLProvider>.value(
            value: provider,
            child: const Scaffold(
              body: AppTopStatusBar(),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('top_bar_settings_button')), findsOneWidget);
      provider.dispose();
    });

    testWidgets('ConnectionScreen (startpage) contains Settings buttons', (tester) async {
      final provider = ECLProvider(
        databaseService: dbService,
        autoLoadDatabase: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ECLProvider>.value(
            value: provider,
            child: const ConnectionScreen(),
          ),
        ),
      );

      // Verify top navigation button
      expect(find.byKey(const Key('startpage_settings_button')), findsOneWidget);

      // Verify main action list button
      expect(find.byKey(const Key('startpage_settings_action_button')), findsOneWidget);

      provider.dispose();
    });

    test('DatabaseService getLastBillingSyncTime returns null when empty and timestamp when cached', () async {
      final initialSync = await dbService.getLastBillingSyncTime();
      expect(initialSync, isNull);

      final meterData = BrunataMeterData.demo();
      await dbService.cacheBrunataData(meterData);

      final cachedSync = await dbService.getLastBillingSyncTime();
      expect(
        DateTime.now().difference(cachedSync!).inSeconds,
        lessThan(5),
      );
    });

    testWidgets('AnalysisSection displays Abrechnungsstelle name and sync timestamp on Heizkosten dieses Jahr card', (tester) async {
      final syncTime = DateTime(2026, 9, 8, 12, 22);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisSection(
                currentOutdoorTemp: 14.5,
                currentFlowTemp: 42.0,
                currentReturnTemp: 34.0,
                parallelShift: 0.0,
                brunataData: BrunataMeterData.demo(),
                lastBillingSyncTime: syncTime,
                billingProviderName: 'Brunata Hamburg',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Heizkosten dieses Jahr'), findsOneWidget);
      expect(find.textContaining('Brunata Hamburg'), findsAtLeastNWidgets(2));
      expect(find.textContaining('12:22'), findsAtLeastNWidgets(1));
    });
  });
}

