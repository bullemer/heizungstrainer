import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/services/license_service.dart';
import 'package:heizungstrainer/services/play_store.dart';

class FakePlayStore implements PlayStoreGateway {
  final controller = StreamController<List<StorePurchase>>.broadcast();
  List<StorePurchase>? owned = [];
  final completed = <StorePurchase>[];
  int buyCalls = 0;

  @override
  Stream<List<StorePurchase>> get purchaseUpdates => controller.stream;

  @override
  Future<StoreProduct?> loadProduct(String productId) async =>
      StoreProduct(id: productId, price: '19,99 €');

  @override
  Future<bool> buy(String productId) async {
    buyCalls++;
    return true;
  }

  @override
  Future<List<StorePurchase>?> ownedPurchases() async => owned;

  @override
  Future<void> complete(StorePurchase purchase) async => completed.add(purchase);
}

StorePurchase _pro(StorePurchaseStatus status, {bool needsCompletion = false}) =>
    StorePurchase(
      productId: proProductId,
      purchaseId: 'GPA.1234',
      status: status,
      needsCompletion: needsCompletion,
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('new purchase unlocks Pro, is stored and acknowledged', () async {
    final store = FakePlayStore();
    final storage = <String, String>{};
    final service = LicenseService(inMemoryStorage: storage, store: store);
    await service.init();
    expect(service.isPro, isFalse);
    expect(service.usesPlayBilling, isTrue);

    expect(await service.buyPro(), isTrue);
    store.controller.add([_pro(StorePurchaseStatus.purchased, needsCompletion: true)]);
    await _settle();

    expect(service.isPro, isTrue);
    expect(service.currentInfo.source, LicenseSource.inAppPurchase);
    expect(service.currentInfo.purchaseId, 'GPA.1234');
    expect(store.completed, hasLength(1));
    expect(LicenseInfo.decode(storage['ecl_license_info']!)!.isPro, isTrue);
  });

  test('pending purchase does not unlock and is not acknowledged', () async {
    final store = FakePlayStore();
    final service = LicenseService(inMemoryStorage: {}, store: store);
    await service.init();

    store.controller.add([_pro(StorePurchaseStatus.pending, needsCompletion: true)]);
    await _settle();

    expect(service.isPro, isFalse);
    expect(service.purchasePending, isTrue);
    expect(store.completed, isEmpty);
  });

  test('restore on start grants Pro owned by the Google account', () async {
    final store = FakePlayStore()..owned = [_pro(StorePurchaseStatus.purchased)];
    final service = LicenseService(inMemoryStorage: {}, store: store);
    await service.init();

    expect(service.isPro, isTrue);
    expect(service.currentInfo.source, LicenseSource.inAppPurchase);
  });

  test('refunded purchase is revoked when Play is reachable', () async {
    final storage = {'ecl_license_info': LicenseInfo.proPlay(purchaseId: 'GPA.1').encode()};
    final store = FakePlayStore()..owned = [];
    final service = LicenseService(inMemoryStorage: storage, store: store);
    await service.init();

    expect(service.isPro, isFalse);
  });

  test('stored purchase survives when Play is unreachable (offline)', () async {
    final storage = {'ecl_license_info': LicenseInfo.proPlay(purchaseId: 'GPA.1').encode()};
    final store = FakePlayStore()..owned = null;
    final service = LicenseService(inMemoryStorage: storage, store: store);
    await service.init();

    expect(service.isPro, isTrue);
    expect(await service.syncWithStore(), isFalse);
    expect(service.isPro, isTrue);
  });

  test('stored Play record is ignored in the website build', () async {
    final storage = {'ecl_license_info': LicenseInfo.proPlay(purchaseId: 'GPA.1').encode()};
    final service = LicenseService(inMemoryStorage: storage);
    await service.init();

    expect(service.isPro, isFalse);
    expect(service.usesPlayBilling, isFalse);
  });

  test('purchase error is surfaced and does not unlock', () async {
    final store = FakePlayStore();
    final service = LicenseService(inMemoryStorage: {}, store: store);
    await service.init();

    store.controller.add([
      const StorePurchase(
        productId: proProductId,
        status: StorePurchaseStatus.error,
        errorMessage: 'BillingResponse.itemUnavailable',
      ),
    ]);
    await _settle();

    expect(service.isPro, isFalse);
    expect(service.purchaseError, 'BillingResponse.itemUnavailable');
  });
}
