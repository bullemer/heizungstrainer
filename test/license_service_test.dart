import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/license_exception.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/license_key.dart';
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
      final pro = LicenseInfo.proOffline(
        licenseKey: 'HT2-AAAAA',
        activatedAt: now,
        customerReference: 'ABCDEF012345',
      );

      final restored = LicenseInfo.decode(pro.encode())!;
      expect(restored.tier, LicenseTier.pro);
      expect(restored.source, LicenseSource.offlineKey);
      expect(restored.licenseKey, 'HT2-AAAAA');
      expect(restored.activatedAt, now);
      expect(restored.customerReference, 'ABCDEF012345');
    });
  });

  group('Ed25519 offline licence keys', () {
    late TestIssuer issuer;
    setUp(() async => issuer = await TestIssuer.create());

    test('a key signed with the matching private key verifies', () async {
      final key = await issuer.issue(licenseId: [1, 2, 3, 4, 5, 6], issuedDay: 277);
      expect(key, startsWith('HT2-'));

      final data = await LicenseKeyCodec.verify(key, issuer.publicKey);
      expect(data, isNotNull);
      expect(data!.licenseId, '010203040506');
      expect(data.issuedAt, DateTime.utc(2026, 10, 5));
      expect(data.edition, LicenseKeyCodec.editionProLifetime);
    });

    test('copy-paste noise (spaces, line breaks, lowercase) is tolerated', () async {
      final key = await issuer.issue();
      final messy = ' ${key.toLowerCase().replaceAll('-', ' - ').replaceFirst(' ', '\n')} ';
      expect(await LicenseKeyCodec.verify(messy, issuer.publicKey), isNotNull);
    });

    test('tampered, foreign-signed, old-format and demo keys are rejected', () async {
      final key = await issuer.issue();
      final other = await TestIssuer.create();
      final foreign = await other.issue();

      // Flip one character in the payload part.
      final chars = key.split('');
      final i = 6;
      chars[i] = chars[i] == 'A' ? 'B' : 'A';
      final tampered = chars.join();

      for (final bad in [
        tampered,
        foreign,
        key.substring(0, key.length - 7),
        'HTPRO-A8C2-91B4-E4F0-77A1', // old HMAC format
        'HT-PRO-DEMO-2026',
        'HT-PRO-DEVELOPER-BYPASS',
        '',
      ]) {
        expect(await LicenseKeyCodec.verify(bad, issuer.publicKey), isNull, reason: bad);
      }
    });

    test('the production public key rejects test-signed keys', () async {
      final key = await issuer.issue();
      expect(await LicenseKeyCodec.verify(key, LicenseKeyCodec.productionPublicKey), isNull);
    });

    test('activates a valid key, persists it and re-verifies on start', () async {
      final inMemory = <String, String>{};
      final service = LicenseService(inMemoryStorage: inMemory, publicKey: issuer.publicKey);
      expect(service.isPro, false);

      final key = await issuer.issue(licenseId: [9, 9, 9, 9, 9, 9]);
      expect(await service.activateOfflineKey(key), true);
      expect(service.isPro, true);
      expect(service.currentInfo.customerReference, '090909090909');

      final reloaded = LicenseService(inMemoryStorage: inMemory, publicKey: issuer.publicKey);
      await reloaded.init();
      expect(reloaded.isPro, true);
    });

    test('an edited stored record does not unlock Pro', () async {
      final forged = <String, String>{
        'ecl_license_info': LicenseInfo.proOffline(licenseKey: 'HT2-FAKE').encode(),
      };
      final service = LicenseService(inMemoryStorage: forged, publicKey: issuer.publicKey);
      await service.init();
      expect(service.isPro, false);

      final testOverride = <String, String>{
        'ecl_license_info': LicenseInfo.proTest().encode(),
      };
      final service2 = LicenseService(inMemoryStorage: testOverride, publicKey: issuer.publicKey);
      await service2.init();
      expect(service2.isPro, false);
    });

    test('rejects invalid key and preserves free tier', () async {
      final service = LicenseService(inMemoryStorage: {}, publicKey: issuer.publicKey);
      expect(await service.activateOfflineKey('HTPRO-FAKE-KEY-0000'), false);
      expect(service.isPro, false);
    });

    test('revokeLicense resets to free tier', () async {
      final service = LicenseService(inMemoryStorage: {}, initialTier: LicenseTier.pro);
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
      expect(find.textContaining('19,99 € einmalig'), findsOneWidget);
      expect(find.textContaining('In-App'), findsNothing);
    });

    testWidgets('entering a valid signed key activates Pro; demo key does not', (tester) async {
      final issuer = (await tester.runAsync(TestIssuer.create))!;
      final key = (await tester.runAsync(() => issuer.issue()))!;
      final freeLicense = LicenseService(
        inMemoryStorage: {},
        initialTier: LicenseTier.free,
        publicKey: issuer.publicKey,
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

      Future<void> submit(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.text('Aktivieren'));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pumpAndSettle();
      }

      await submit('HT-PRO-DEMO-2026');
      expect(freeLicense.isPro, false);
      expect(find.textContaining('Ungültiger Lizenzschlüssel'), findsOneWidget);

      await submit(key);
      expect(freeLicense.isPro, true);
    });
  });
}

/// Signs keys in the production format with a throwaway Ed25519 key pair.
class TestIssuer {
  TestIssuer._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;
  final List<int> publicKey;

  static Future<TestIssuer> create() async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    return TestIssuer._(keyPair, publicKey);
  }

  Future<String> issue({
    List<int> licenseId = const [0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45],
    int issuedDay = 0,
    int edition = LicenseKeyCodec.editionProLifetime,
  }) async {
    final payload = [
      LicenseKeyCodec.formatVersion,
      ...licenseId,
      (issuedDay >> 8) & 0xFF,
      issuedDay & 0xFF,
      edition,
    ];
    final signature = await Ed25519().sign(payload, keyPair: _keyPair);
    return LicenseKeyCodec.format([...payload, ...signature.bytes]);
  }
}
