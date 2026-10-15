import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'package:heizungstrainer/services/discovery_service.dart';
import 'package:heizungstrainer/services/license_service.dart';
import 'package:heizungstrainer/services/play_store.dart';

import 'play_billing_test.dart' show FakePlayStore;

SK2Transaction _tx({String productId = proProductId, Map<String, Object?>? json}) => SK2Transaction(
      id: '2000000123',
      originalId: '2000000123',
      productId: productId,
      purchaseDate: '0',
      appAccountToken: null,
      jsonRepresentation: json == null ? null : jsonEncode(json),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('App Store purchases', () {
    tearDown(() => debugAppStoreBuildOverride = null);

    test('iPhone is a store build with App Store texts', () {
      debugAppStoreBuildOverride = true;
      expect(isStoreBuild, isTrue);
      expect(storeName, 'App Store');
      expect(storeAccountName, 'Apple-Account');
    });

    test('empty transaction history means "could not ask" and never revokes', () {
      expect(InAppPurchaseGateway.appStorePurchasesFrom([]), isNull);
    });

    test('verified Pro transaction counts as purchased', () {
      final owned = InAppPurchaseGateway.appStorePurchasesFrom([_tx(json: {'productId': proProductId})])!;
      expect(owned.single.productId, proProductId);
      expect(owned.single.status, StorePurchaseStatus.purchased);
    });

    test('refunded transaction (revocationDate) is not owned', () {
      final owned = InAppPurchaseGateway.appStorePurchasesFrom([
        _tx(json: {'productId': proProductId, 'revocationDate': 1760000000000}),
      ])!;
      expect(owned.single.status, StorePurchaseStatus.canceled);
    });

    test('restore button refreshes from the store first, app start does not', () async {
      final store = FakePlayStore();
      final service = LicenseService(inMemoryStorage: {}, store: store);
      await service.init();
      expect(store.refreshCalls, 0);

      await service.syncWithStore(userInitiated: true);
      expect(store.refreshCalls, 1);
    });
  });

  group('iOS local network', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('Android keeps the location permission, iOS does not need it', () {
      expect(DiscoveryService(isIOS: false).needsLocationPermission, isTrue);
      expect(DiscoveryService(isIOS: true).needsLocationPermission, isFalse);
    });

    test('prompt is triggered once on iOS and waits for the answer', () async {
      var waits = 0;
      final service = DiscoveryService(isIOS: true, awaitPermissionAnswer: () async => waits++);
      await service.ensureLocalNetworkPrompt('127.0.0');
      await service.ensureLocalNetworkPrompt('127.0.0');
      expect(waits, 1);
    });

    test('no prompt handling on Android', () async {
      var waits = 0;
      final service = DiscoveryService(isIOS: false, awaitPermissionAnswer: () async => waits++);
      await service.ensureLocalNetworkPrompt('127.0.0');
      expect(waits, 0);
    });

    test('scan looks blocked only if nothing answered and failures were instant', () {
      final blocked = List.filled(254, ProbeResult.instantError);
      expect(DiscoveryService.scanLooksBlocked(blocked), isTrue);

      // Normal home network: absent hosts time out, the router refuses.
      final normal = [ProbeResult.refused, ...List.filled(253, ProbeResult.timeout)];
      expect(DiscoveryService.scanLooksBlocked(normal), isFalse);

      // Instant errors but the router answered → network reachable.
      final answered = [ProbeResult.refused, ...List.filled(253, ProbeResult.instantError)];
      expect(DiscoveryService.scanLooksBlocked(answered), isFalse);

      expect(DiscoveryService.scanLooksBlocked([]), isFalse);
    });
  });
}
