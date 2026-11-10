import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/app_version.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  Widget buildSettingsScreen(ECLProvider provider) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: ChangeNotifierProvider<ECLProvider>.value(
        value: provider,
        child: const SettingsScreen(),
      ),
    );
  }

  group('SettingsScreen Beta write gate', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    testWidgets('Beta controller shows read-only card; enabling needs confirmation',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);
      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      // Danfoss (verified): no gate card.
      expect(find.byKey(const Key('betaWriteSwitch')), findsNothing);

      await provider.setSelectedController('nibe_modbus');
      await tester.pumpAndSettle();
      expect(find.text('Beta-Treiber: Schreibzugriff'), findsOneWidget);
      expect(find.text('Beta'), findsWidgets);

      // Cancelling the warning keeps writes blocked.
      await tester.ensureVisible(find.byKey(const Key('betaWriteSwitch')));
      await tester.tap(find.byKey(const Key('betaWriteSwitch')));
      await tester.pumpAndSettle();
      expect(find.text('Verstanden, freigeben'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(provider.betaWritesEnabled, isFalse);

      // Confirming enables them.
      await tester.tap(find.byKey(const Key('betaWriteSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verstanden, freigeben'));
      await tester.pumpAndSettle();
      expect(provider.betaWritesEnabled, isTrue);
    });
  });

  group('SettingsScreen Multi-Controller & Billing Selection Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    testWidgets('renders all controllers, billing providers and the building section',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      // Title; no duplicate "Aktives Setup" summary of controller + billing
      expect(find.text('Einstellungen & Hardware'), findsOneWidget);
      expect(find.text('Aktives Setup'), findsNothing);
      expect(find.text('Gebäude & Heizsystem'), findsOneWidget);
      expect(find.byKey(const Key('buildingProfileCard')), findsOneWidget);

      // Section Headers
      expect(find.text('Heizungsregler (Hardware)'), findsOneWidget);
      expect(find.text('Sicherer Fernzugriff (FRITZ!Box WireGuard®)'), findsOneWidget);
      expect(find.text('Messdienstleister & Abrechnung'), findsOneWidget);
      expect(find.text('Tarif & Energiepreis'), findsOneWidget);
      expect(find.text('Datenpuffer & Offline-Betrieb'), findsOneWidget);
      expect(find.text('Version $appVersionLabel'), findsOneWidget);

      // Known Controllers
      expect(find.text('Danfoss'), findsWidgets);
      expect(find.text('ECL Comfort 310 / 210'), findsWidgets);
      expect(find.text('Viessmann'), findsOneWidget);
      expect(find.text('Vitotronic & ViCare'), findsOneWidget);
      expect(find.text('Bosch / Buderus'), findsOneWidget);
      expect(find.text('Vaillant'), findsOneWidget);
      expect(find.text('Weishaupt'), findsOneWidget);
      expect(find.text('NIBE'), findsOneWidget);
      expect(find.text('Generisch'), findsOneWidget);

      // Known Billing Providers
      expect(find.text('Brunata Hamburg'), findsWidgets);
      expect(find.text('Brunata München'), findsOneWidget);
      expect(find.text('Brunata Hürth'), findsOneWidget);
      expect(find.text('KALO (Kalorimeta)'), findsOneWidget);
      expect(find.text('Techem Smart System'), findsOneWidget);
      expect(find.text('ista EcoTrend (Essen)'), findsOneWidget);
      expect(find.text('Minol Messtechnik'), findsOneWidget);

      // One save button (fetching billing data is in the billing card)
      expect(find.byKey(const Key('saveSettings')), findsOneWidget);
      expect(find.text('Nur speichern'), findsNothing);
      expect(find.text('Protokoll & Diagnose öffnen'), findsNothing); // Logs is a tab
    });

    testWidgets('selecting Viessmann controller updates state and shows hardware config card',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      expect(provider.selectedControllerId, 'danfoss_ecl_310');

      // Tap Viessmann card
      await tester.tap(find.text('Vitotronic & ViCare'));
      await tester.pumpAndSettle();

      expect(provider.selectedControllerId, 'viessmann_vicare');
      expect(provider.isSimulatedController, isFalse);
      expect(find.text('Viessmann Vitotronic & ViCare Konfiguration'), findsOneWidget);
    });

    testWidgets('selecting Vaillant controller updates state and shows eBUSd config card',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text('eBUS / eBUSd Gateway'));
      await tester.pumpAndSettle();

      expect(provider.selectedControllerId, 'vaillant_ebusd');
      expect(provider.isSimulatedController, isFalse);
      expect(find.text('Vaillant eBUSd Gateway Konfiguration'), findsOneWidget);
    });

    testWidgets('selecting Weishaupt controller updates state and shows WEM config card',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wärmepumpen (Modbus TCP)'));
      await tester.pumpAndSettle();

      expect(provider.selectedControllerId, 'weishaupt_wem');
      expect(provider.isSimulatedController, isFalse);
      expect(find.text('Weishaupt WEM Gateway Konfiguration'), findsOneWidget);
    });

    testWidgets('selecting NIBE controller updates state and shows Modbus config card',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text('S-Serie & F-Serie (Modbus TCP)'));
      await tester.pumpAndSettle();

      expect(provider.selectedControllerId, 'nibe_modbus');
      expect(provider.isSimulatedController, isFalse);
      expect(find.text('NIBE Wärmepumpe Konfiguration'), findsOneWidget);
    });

    testWidgets('selecting Techem billing provider updates state and displays simulation note',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      expect(provider.selectedBillingId, 'brunata_hamburg');
      // Initially Brunata credentials fields are visible
      expect(find.text('Brunata Portal-Zugang'), findsOneWidget);

      // Tap Techem card
      await tester.tap(find.text('Techem Smart System'));
      await tester.pumpAndSettle();

      expect(provider.selectedBillingId, 'techem_smart');
      expect(provider.currentBillingDescriptor.isSupported, isFalse);

      // Brunata credentials hidden, Techem notice visible
      expect(find.text('Brunata Portal-Zugang'), findsNothing);
      expect(find.textContaining('Simulationsmodus'), findsWidgets);
    });

    testWidgets('billing provider selection is combined with credentials fields and Live badge is removed',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      // Ensure 'Live' badge is removed and NOT present
      expect(find.text('Live'), findsNothing);

      // Initially Brunata is selected: its credentials form is rendered inline
      expect(find.text('Brunata Portal-Zugang'), findsOneWidget);
      expect(find.text('Kundennummer / Benutzername'), findsOneWidget);
      expect(find.text('Kennwort / Passwort'), findsOneWidget);
      expect(find.text('Portal-URL / Endpunkt (optional)'), findsOneWidget);
      expect(find.text('Brunata Hamburg Daten abrufen'), findsOneWidget);

      // Tap KALO provider
      await tester.tap(find.text('KALO (Kalorimeta)'));
      await tester.pumpAndSettle();

      expect(provider.selectedBillingId, 'kalo');
      // Brunata credentials collapsed, KALO credentials expanded inline
      expect(find.text('Brunata Portal-Zugang'), findsNothing);
      expect(find.text('KALO Bewohnerportal-Zugang'), findsOneWidget);
      expect(find.text('E-Mail / Bewohner-ID / Kundennummer'), findsOneWidget);
      expect(find.text('KALO (Kalorimeta) Daten abrufen'), findsOneWidget);
    });

    testWidgets('displays realistic energy carrier chips, allows switching and user overwrite',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      // Check Section 3 elements
      expect(find.text('Tarif & Energiepreis'), findsOneWidget);
      expect(find.text('Marktpreis abrufen'), findsNothing); // removed: it never fetched a price
      expect(find.textContaining('Fernwärme Hamburg'), findsWidgets);
      expect(find.textContaining('Erdgas Deutschland'), findsWidgets);
      expect(find.textContaining('Wärmepumpe'), findsWidgets);

      // Default price for Brunata Hamburg is Fernwärme Hamburg (0.132)
      final priceField = find.widgetWithText(TextFormField, 'Arbeitspreis pro kWh (manuell anpassbar)');
      expect(priceField, findsOneWidget);
      expect(find.text('0.132'), findsWidgets);

      // Select Erdgas Deutschland chip (0.118)
      await tester.tap(find.textContaining('Erdgas Deutschland'));
      await tester.pumpAndSettle();

      expect(find.text('0.118'), findsWidgets);

      // User manual overwrite
      await tester.enterText(priceField, '0.145');
      await tester.pumpAndSettle();

      expect(find.text('0.145'), findsOneWidget);
      expect(find.text('Manueller Vertragspreis'), findsOneWidget);
    });

    testWidgets('renders WireGuard remote access card and toggles step-by-step guide',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      // Card is present
      expect(find.text('Fernzugriff via FRITZ!Box WireGuard®'), findsOneWidget);
      expect(find.text('ohne Cloud-Dienst'), findsWidgets);

      // Steps are not visible initially
      expect(find.text('FRITZ!Box WireGuard® aktivieren'), findsNothing);

      // Tap card to expand
      await tester.tap(find.text('Fernzugriff via FRITZ!Box WireGuard®'));
      await tester.pumpAndSettle();

      // Now all 4 steps and security info are visible
      expect(find.text('Einrichtung in 4 einfachen Schritten:'), findsOneWidget);
      expect(find.text('FRITZ!Box WireGuard® aktivieren'), findsOneWidget);
      expect(find.text('WireGuard App einrichten'), findsOneWidget);
      expect(find.text('Feste IP für Heizungsregler festlegen'), findsOneWidget);
      expect(find.text('Von unterwegs verbinden & heizen'), findsOneWidget);
      expect(find.textContaining('Warum WireGuard VPN?'), findsOneWidget);

      // Tap card again to collapse
      await tester.tap(find.text('Fernzugriff via FRITZ!Box WireGuard®'));
      await tester.pumpAndSettle();
      expect(find.text('Einrichtung in 4 einfachen Schritten:'), findsNothing);
    });
  });

  group('SettingsScreen controller IP', () {
    testWidgets('shows the saved controller IP on the selected Danfoss card', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'ecl_controller_ip': '192.168.178.47'});
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final provider = ECLProvider(autoLoadDatabase: false);

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('controllerIpAddress')), findsOneWidget);
      expect(find.text('IP-Adresse: 192.168.178.47'), findsOneWidget);
    });

    testWidgets('shows the live IP while connected', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final provider = ECLProvider(autoLoadDatabase: false);
      provider.setConnectedForTesting(ip: '10.0.0.12');

      await tester.pumpWidget(buildSettingsScreen(provider));
      await tester.pumpAndSettle();

      expect(find.text('IP-Adresse: 10.0.0.12 · verbunden'), findsOneWidget);
    });
  });
}
