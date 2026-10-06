import 'dart:async';

import 'package:flutter/services.dart' show appFlavor;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// True for the Google Play build (`--flavor play`). The website APK is the
/// `direct` flavor and keeps the offline HT2 licence keys.
bool get isPlayBuild => appFlavor == 'play';

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
