import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show appFlavor;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// True for the Google Play build (`--flavor play`). The website APK is the
/// `direct` flavor and keeps the offline HT2 licence keys.
bool get isPlayBuild => appFlavor == 'play';

/// Tests set this to run the iOS code paths on the host.
@visibleForTesting
bool? debugAppStoreBuildOverride;

/// True on iPhone: the only way to install there is the App Store, so Pro is
/// always sold through Apple in-app purchase.
bool get isAppStoreBuild => debugAppStoreBuildOverride ?? (!kIsWeb && Platform.isIOS);

/// Pro is sold through a store (Google Play or the App Store), not keys.
bool get isStoreBuild => isPlayBuild || isAppStoreBuild;

/// Store name for user-facing texts.
String get storeName => isAppStoreBuild ? 'App Store' : 'Google Play';

/// Account the store ties purchases to, for user-facing texts.
String get storeAccountName => isAppStoreBuild ? 'Apple-Account' : 'Google-Konto';

/// Apple's numeric app id (App Store Connect → App Information), needed to
/// open the listing on iOS. Empty until the app exists in App Store Connect.
const String appStoreId = '';

/// Product id of the one-time "Heizungstrainer Pro" purchase in Play Console.
const String proProductId = 'heizungstrainer_pro';

enum StorePurchaseStatus { pending, purchased, canceled, error }

/// A Play purchase reduced to what the licence logic needs.
class StorePurchase {
  final String productId;
  final String? purchaseId;
  final StorePurchaseStatus status;
  final bool needsCompletion;
  final String? errorMessage;

  /// Platform object, handed back to [PlayStoreGateway.complete].
  final Object? raw;

  const StorePurchase({
    required this.productId,
    required this.status,
    this.purchaseId,
    this.needsCompletion = false,
    this.errorMessage,
    this.raw,
  });
}

/// Product as shown in the upgrade dialog (price localised by Play).
class StoreProduct {
  final String id;
  final String price;

  const StoreProduct({required this.id, required this.price});
}

/// Thin seam over Google Play Billing so [LicenseService] can be tested.
abstract class PlayStoreGateway {
  /// Purchases reported by Play (new buys, pending → purchased transitions).
  Stream<List<StorePurchase>> get purchaseUpdates;

  Future<StoreProduct?> loadProduct(String productId);

  /// Starts the Play purchase flow. The result arrives on [purchaseUpdates].
  Future<bool> buy(String productId);

  /// Purchases Play currently holds for this Google account, or null if Play
  /// couldn't be asked (offline, no Play services) – null must never revoke.
  Future<List<StorePurchase>?> ownedPurchases();

  /// Acknowledges a purchase. Play refunds purchases not acknowledged within
  /// three days.
  Future<void> complete(StorePurchase purchase);

  /// Before a user-initiated restore: makes the store fetch the account's
  /// purchases from its servers (App Store may ask for the Apple password).
  Future<void> refreshFromServer();
}

class InAppPurchaseGateway implements PlayStoreGateway {
  final InAppPurchase _iap;
  final Map<String, ProductDetails> _products = {};

  InAppPurchaseGateway({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  @override
  Stream<List<StorePurchase>> get purchaseUpdates =>
      _iap.purchaseStream.map((list) => list.map(_convert).toList());

  @override
  Future<StoreProduct?> loadProduct(String productId) async {
    if (!await _iap.isAvailable()) return null;
    final response = await _iap.queryProductDetails({productId});
    if (response.productDetails.isEmpty) return null;
    final details = response.productDetails.first;
    _products[productId] = details;
    return StoreProduct(id: details.id, price: details.price);
  }

  @override
  Future<bool> buy(String productId) async {
    final details = _products[productId];
    if (details == null && await loadProduct(productId) == null) return false;
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: _products[productId]!),
    );
  }

  @override
  Future<List<StorePurchase>?> ownedPurchases() async {
    try {
      if (!await _iap.isAvailable()) return null;
      if (isAppStoreBuild) return appStorePurchasesFrom(await SK2Transaction.transactions());
      final addition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      if (response.error != null) return null;
      return response.pastPurchases.map(_convert).toList();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    final raw = purchase.raw;
    if (raw is PurchaseDetails) await _iap.completePurchase(raw);
  }

  @override
  Future<void> refreshFromServer() async {
    // Play's purchase query already asks the servers.
    if (isAppStoreBuild) await AppStore().sync();
  }

  /// Maps StoreKit 2's verified transaction history to purchases.
  ///
  /// An empty history returns null ("couldn't ask"): StoreKit may not have
  /// synced it yet on a new device or offline, and that must never revoke Pro.
  /// A refunded purchase stays in the history with a `revocationDate` and is
  /// reported as cancelled, which revokes a stored App Store licence.
  @visibleForTesting
  static List<StorePurchase>? appStorePurchasesFrom(List<SK2Transaction> transactions) {
    if (transactions.isEmpty) return null;
    return transactions
        .map((t) => StorePurchase(
              productId: t.productId,
              purchaseId: t.id,
              status: _isRevoked(t.jsonRepresentation)
                  ? StorePurchaseStatus.canceled
                  : StorePurchaseStatus.purchased,
            ))
        .toList();
  }

  static bool _isRevoked(String? json) {
    if (json == null || json.isEmpty) return false;
    try {
      final decoded = jsonDecode(json);
      return decoded is Map && decoded['revocationDate'] != null;
    } catch (_) {
      return false;
    }
  }

  static StorePurchase _convert(PurchaseDetails p) {
    final status = switch (p.status) {
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.purchased || PurchaseStatus.restored => StorePurchaseStatus.purchased,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
      PurchaseStatus.error => StorePurchaseStatus.error,
    };
    return StorePurchase(
      productId: p.productID,
      purchaseId: p.purchaseID,
      status: status,
      needsCompletion: p.pendingCompletePurchase,
      errorMessage: p.error?.message,
      raw: p,
    );
  }
}
