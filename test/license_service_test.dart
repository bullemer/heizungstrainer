import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/license_exception.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/license_service.dart';
import 'package:heizungstrainer/widgets/pro_upgrade_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LicenseInfo Model Tests', () {
    test('default free license has correct properties', () {
      final free = LicenseInfo.free();
      expect(free.tier, LicenseTier.free);
      expect(free.source, LicenseSource.none);
      expect(free.isPro, false);
      expect(free.licenseKey, isNull);
    });

    test('proOffline constructor sets correct fields', () {
      final now = DateTime(2026, 9, 8, 20, 0);
      final pro = LicenseInfo.proOffline(
        licenseKey: 'HTPRO-ABCD-1234-EF56-7890',
        activatedAt: now,
        customerReference: 'cust_42',
      );

      expect(pro.tier, LicenseTier.pro);
      expect(pro.source, LicenseSource.offlineKey);
      expect(pro.isPro, true);
      expect(pro.licenseKey, 'HTPRO-ABCD-1234-EF56-7890');
      expect(pro.activatedAt, now);
      expect(pro.customerReference, 'cust_42');
    });

    test('serializes and deserializes accurately', () {
      final now = DateTime(2026, 9, 8, 20, 0);
      final pro = LicenseInfo.proInApp(
        purchaseId: 'GPA.1234-5678',
        productId: LicenseService.proLifetimeProductId,
        activatedAt: now,
      );

      final json = pro.toJson();
      final restored = LicenseInfo.fromJson(json);

      expect(restored.tier, LicenseTier.pro);
      expect(restored.source, LicenseSource.inAppPurchase);
      expect(restored.purchaseId, 'GPA.1234-5678');
      expect(restored.productId, LicenseService.proLifetimeProductId);
      expect(restored.activatedAt, now);
      expect(restored.isPro, true);

      final encoded = pro.encode();
      final decoded = LicenseInfo.decode(encoded);
      expect(decoded?.purchaseId, 'GPA.1234-5678');
    });
  });

  group('LicenseService Offline Key Cryptography Tests', () {
    test('verifies predefined demo keys', () {
      expect(LicenseService.verifyOfflineKey('HT-PRO-DEMO-2026'), true);
      expect(LicenseService.verifyOfflineKey('HTPRO-TEST-KEY-VALID'), true);
      expect(LicenseService.verifyOfflineKey(' ht-pro-demo-2026 '), true);
    });

    test('dynamically generated key validates successfully', () {
      final key = LicenseService.generateKey();
      expect(key.startsWith('HTPRO-'), true);
      expect(LicenseService.verifyOfflineKey(key), true);
    });

    test('tampered or invalid keys fail verification', () {
      final validKey = LicenseService.generateKey();
      // Corrupt the last character
      final corrupted = validKey.substring(0, validKey.length - 1) +
          (validKey.endsWith('A') ? 'B' : 'A');

      expect(LicenseService.verifyOfflineKey(corrupted), false);
      expect(LicenseService.verifyOfflineKey('HTPRO-INVALID-KEY'), false);
      expect(LicenseService.verifyOfflineKey('RANDOM-STRING-123'), false);
      expect(LicenseService.verifyOfflineKey(''), false);
    });

    test('activates offline key and persists into in-memory storage', () async {
      final inMemory = <String, String>{};
      final service = LicenseService(inMemoryStorage: inMemory);

      expect(service.isPro, false);
      expect(service.canWriteParameters, false);

      final validKey = LicenseService.generateKey();
      final activated = await service.activateOfflineKey(validKey);

      expect(activated, true);
      expect(service.isPro, true);
      expect(service.canWriteParameters, true);
      expect(service.currentInfo.source, LicenseSource.offlineKey);

      // Re-initialize from storage
      final reloadedService = LicenseService(inMemoryStorage: inMemory);
      await reloadedService.init();
      expect(reloadedService.isPro, true);
      expect(reloadedService.currentInfo.licenseKey, validKey.toUpperCase());
    });

    test('rejects invalid key and preserves free tier', () async {
      final service = LicenseService(inMemoryStorage: {});
      final result = await service.activateOfflineKey('HTPRO-FAKE-KEY-0000');

      expect(result, false);
      expect(service.isPro, false);
    });
  });

  group('LicenseService In-App Purchase & Lifecycle Tests', () {
    test('activates and restores in-app purchase', () async {
      final service = LicenseService(inMemoryStorage: {});

      final success = await service.activateInAppPurchase(
        purchaseId: 'GPA.999-888',
        productId: LicenseService.proLifetimeProductId,
      );

      expect(success, true);
      expect(service.isPro, true);
      expect(service.currentInfo.source, LicenseSource.inAppPurchase);

      final restored = await service.restorePurchases();
      expect(restored, true);
    });

    test('revokeLicense resets to free tier', () async {
      final service = LicenseService(
        inMemoryStorage: {},
        initialTier: LicenseTier.pro,
      );
      expect(service.isPro, true);

      await service.revokeLicense();
      expect(service.isPro, false);
      expect(service.currentTier, LicenseTier.free);
    });
  });

  group('ECLProvider Write Gating with License Gate', () {
    test('writeParameter is blocked when license is free tier', () async {
      final logService = ActivityLogService(
        enablePersistence: false,
        enableRemoteDispatch: false,
      );
      final freeLicense = LicenseService(
        inMemoryStorage: {},
        initialTier: LicenseTier.free,
      );

      final provider = ECLProvider(
        logService: logService,
        licenseService: freeLicense,
        autoLoadDatabase: false,
      );

      // Start simulation so isConnected is true
      await provider.startSimulation();
      expect(provider.isConnected, true);

      expect(
        () => provider.writeParameter(ECLRegisters.heatingCurveShift, 1.0),
        throwsA(isA<LicenseRequiredException>()),
      );

      // Check security gate audit entry
      expect(
        logService.recentEntries.any((e) => e.errorCode == 'LICENSE_PRO_REQUIRED'),
        true,
      );
    });

    test('writeParameter succeeds when license is Pro tier', () async {
      final logService = ActivityLogService(
        enablePersistence: false,
        enableRemoteDispatch: false,
      );
      final proLicense = LicenseService(
        inMemoryStorage: {},
        initialTier: LicenseTier.pro,
      );

      final provider = ECLProvider(
        logService: logService,
        licenseService: proLicense,
        autoLoadDatabase: false,
      );

      await provider.startSimulation();
      expect(provider.isConnected, true);

      final reading = await provider.writeParameter(
        ECLRegisters.heatingCurveShift,
        1.0,
      );
      expect(reading.displayValue, 1.0);
    });
  });

  group('ProUpgradeDialog Widget Tests', () {
    testWidgets('renders modal with feature rows and activation options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final freeLicense = LicenseService(
        inMemoryStorage: {},
        initialTier: LicenseTier.free,
      );
      final provider = ECLProvider(
        licenseService: freeLicense,
        autoLoadDatabase: false,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: ProUpgradeDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Heizungstrainer Pro'), findsOneWidget);
      expect(find.text('Sensoren & Zähler live lesen'), findsOneWidget);
      expect(find.text('Heizkurven-Shift direkt schreiben'), findsOneWidget);
      expect(find.text('Aktivieren'), findsOneWidget);
      expect(find.textContaining('Einmalkauf'), findsOneWidget);
    });

    testWidgets('entering valid demo key activates Pro', (tester) async {
      final freeLicense = LicenseService(
        inMemoryStorage: {},
        initialTier: LicenseTier.free,
      );
      final provider = ECLProvider(
        licenseService: freeLicense,
        autoLoadDatabase: false,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: ProUpgradeDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter demo key
      await tester.enterText(find.byType(TextField), 'HT-PRO-DEMO-2026');
      await tester.tap(find.text('Aktivieren'));
      await tester.pumpAndSettle();

      expect(freeLicense.isPro, true);
    });
  });
}
