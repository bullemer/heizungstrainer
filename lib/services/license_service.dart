import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/services/license_key.dart';
import 'package:heizungstrainer/services/play_store.dart';

/// Central licensing and entitlement service for Heizungstrainer.
///
/// Pro is unlocked with an offline licence key signed with Ed25519 (see
/// [LicenseKeyCodec]). The app only contains the public key, so keys can be
/// checked without internet but not forged from the APK. The stored licence is
/// re-verified on every start, so editing the stored record doesn't unlock Pro.
///
/// Free launch phase ([freeLaunchPhase]): everything is unlocked and every
/// install is marked as early adopter (separate storage key, never touched by
/// purchases or key revocation). Early adopters keep Pro for life once the
/// phase ends and Pro becomes a paid upgrade.
///
/// The Google Play build sells Pro through Play Billing instead ([store]): a
/// stored Play purchase counts until Play, when reachable, no longer reports
/// it (refund), so Pro keeps working offline.
/// While true, Pro is free for everyone and installs become early adopters.
/// Set to false (in an app update) to start charging for Pro.
const bool freeLaunchPhase = true;

class LicenseService extends ChangeNotifier {
  static const String _storageKey = 'ecl_license_info';
  static const String _earlyAdopterKey = 'ht_early_adopter_since';

  final FlutterSecureStorage? _secureStorage;
  final Map<String, String>? _inMemoryStorage;
  final List<int> _publicKey;
  final PlayStoreGateway? _store;
  final bool _freeLaunch;
  DateTime? _earlyAdopterSince;
  StreamSubscription<List<StorePurchase>>? _storeSubscription;

  LicenseInfo _currentInfo;
  bool _isInitialized = false;
  bool _purchasePending = false;
  String? _purchaseError;

  LicenseService({
    FlutterSecureStorage? secureStorage,
    Map<String, String>? inMemoryStorage,
    LicenseTier? initialTier,
    PlayStoreGateway? store,
    bool freeLaunch = false,
    @visibleForTesting List<int>? publicKey,
  })  : _store = store,
        _freeLaunch = freeLaunch,
        _publicKey = publicKey ?? LicenseKeyCodec.productionPublicKey,
        _secureStorage = inMemoryStorage != null
            ? null
            : (secureStorage ?? const FlutterSecureStorage()),
        _inMemoryStorage = inMemoryStorage,
        _currentInfo = initialTier == LicenseTier.pro
            ? LicenseInfo.proTest(note: 'Initial Test Pro')
            : LicenseInfo.free();

  /// Effective license state: a key or purchase wins, then early adopter.
  LicenseInfo get currentInfo {
    if (_currentInfo.isPro) return _currentInfo;
    final since = _earlyAdopterSince;
    if (since != null) return LicenseInfo.earlyAdopter(since: since);
    return _currentInfo;
  }

  /// Current tier (free or pro).
  LicenseTier get currentTier => isPro ? LicenseTier.pro : LicenseTier.free;

  /// Whether the user has unlocked Pro features.
  bool get isPro => _freeLaunch || _currentInfo.isPro || _earlyAdopterSince != null;

  /// Free launch phase: no upgrade/purchase UI, everything unlocked.
  bool get isFreeLaunch => _freeLaunch;

  /// Installed during the free launch phase (Pro for life).
  bool get isEarlyAdopter => _earlyAdopterSince != null;

  /// Since when this install is an early adopter.
  DateTime? get earlyAdopterSince => _earlyAdopterSince;

  /// Whether the service has completed loading from secure storage.
  bool get isInitialized => _isInitialized;

  /// Whether Pro is sold through Google Play (Play build) rather than keys.
  bool get usesPlayBilling => _store != null;

  /// A Play purchase is waiting for payment (e.g. cash at a shop).
  bool get purchasePending => _purchasePending;

  /// Last Play purchase error, for the upgrade dialog.
  String? get purchaseError => _purchaseError;

  // ── Feature Gates ─────────────────────────────────────────────────────────

  /// Gated: Writing setpoints (heating curve shift, room target) directly to hardware.
  bool get canWriteParameters => isPro;

  /// Gated: Automatically applying holiday & absence setbacks to controller hardware.
  bool get canUseHolidayAutoWrite => isPro;

  /// Gated: Restoring backup snapshots into controller EEPROM/registers.
  bool get canRestoreBackups => isPro;

  // ── Initialization & Storage ──────────────────────────────────────────────

  /// Loads stored license state from encrypted storage.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _loadEarlyAdopter();
      final raw = await _read(_storageKey);

      if (raw != null && raw.isNotEmpty) {
        final loaded = LicenseInfo.decode(raw);
        if (loaded != null && loaded.isPro) {
          // Only a stored key that still verifies counts; anything else (old
          // HMAC/demo keys, simulated purchases, edited records) falls back to Free.
          final key = loaded.source == LicenseSource.offlineKey ? loaded.licenseKey : null;
          if (_store != null && loaded.source == LicenseSource.inAppPurchase) {
            _currentInfo = loaded;
          } else if (key != null && await verifyOfflineKey(key) != null) {
            _currentInfo = loaded;
          } else {
            debugPrint('[LicenseService] Stored licence not valid any more – using Free.');
          }
        }
      }
    } catch (e) {
      debugPrint('[LicenseService] Error loading stored license: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }

    if (_store != null) {
      _storeSubscription ??= _store.purchaseUpdates.listen(
        _handlePurchases,
        onError: (Object e) => debugPrint('[LicenseService] Play purchase stream: $e'),
      );
      await syncWithStore();
    }
  }

  Future<String?> _read(String key) async {
    if (_inMemoryStorage != null) return _inMemoryStorage[key];
    return _secureStorage?.read(key: key);
  }

  Future<void> _write(String key, String value) async {
    if (_inMemoryStorage != null) {
      _inMemoryStorage[key] = value;
    } else {
      await _secureStorage?.write(key: key, value: value);
    }
  }

  /// Reads the early-adopter mark; during the launch phase sets it once.
  Future<void> _loadEarlyAdopter() async {
    try {
      final raw = await _read(_earlyAdopterKey);
      _earlyAdopterSince = raw == null ? null : DateTime.tryParse(raw);
      if (_earlyAdopterSince == null && _freeLaunch) {
        final now = DateTime.now();
        await _write(_earlyAdopterKey, now.toIso8601String());
        _earlyAdopterSince = now;
      }
    } catch (e) {
      debugPrint('[LicenseService] Early-adopter mark not readable/writable: $e');
    }
  }

  // ── Google Play Billing ───────────────────────────────────────────────────

  /// Loads the Pro product with its localised price, or null if Play is
  /// unavailable or the product isn't set up.
  Future<StoreProduct?> loadProProduct() async {
    final store = _store;
    if (store == null) return null;
    try {
      return await store.loadProduct(proProductId);
    } catch (e) {
      debugPrint('[LicenseService] Loading Play product failed: $e');
      return null;
    }
  }

  /// Starts the Play purchase flow; the outcome arrives via the purchase stream.
  Future<bool> buyPro() async {
    final store = _store;
    if (store == null) return false;
    _purchaseError = null;
    notifyListeners();
    try {
      return await store.buy(proProductId);
    } catch (e) {
      _purchaseError = 'Kauf konnte nicht gestartet werden: $e';
      notifyListeners();
      return false;
    }
  }

  /// Asks Play which purchases this Google account owns ("Käufe
  /// wiederherstellen", and on every start). Grants Pro for an owned purchase
  /// and revokes a stored Play licence Play no longer reports (refund).
  /// Returns false if Play couldn't be reached – nothing changes then.
  Future<bool> syncWithStore() async {
    final store = _store;
    if (store == null) return false;
    final owned = await store.ownedPurchases();
    if (owned == null) return false;

    final pro = owned.where((p) => p.productId == proProductId).toList();
    await _handlePurchases(pro);
    final ownsPro = pro.any((p) => p.status == StorePurchaseStatus.purchased);
    _purchasePending = !ownsPro && pro.any((p) => p.status == StorePurchaseStatus.pending);
    if (!ownsPro && _currentInfo.source == LicenseSource.inAppPurchase) {
      debugPrint('[LicenseService] Play no longer reports the Pro purchase – using Free.');
      await _persist(LicenseInfo.free());
    } else {
      notifyListeners();
    }
    return true;
  }

  Future<void> _handlePurchases(List<StorePurchase> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productId != proProductId) continue;
      switch (purchase.status) {
        case StorePurchaseStatus.pending:
          _purchasePending = true;
          _purchaseError = null;
        case StorePurchaseStatus.purchased:
          _purchasePending = false;
          _purchaseError = null;
          // An offline key already unlocks Pro; don't replace it.
          if (_currentInfo.source != LicenseSource.offlineKey) {
            await _persist(LicenseInfo.proPlay(
              purchaseId: purchase.purchaseId,
              productId: purchase.productId,
              activatedAt: _currentInfo.source == LicenseSource.inAppPurchase
                  ? _currentInfo.activatedAt
                  : null,
            ));
          }
        case StorePurchaseStatus.canceled:
          _purchasePending = false;
        case StorePurchaseStatus.error:
          _purchasePending = false;
          _purchaseError = purchase.errorMessage ?? 'Kauf fehlgeschlagen.';
      }
      if (purchase.needsCompletion && purchase.status != StorePurchaseStatus.pending) {
        try {
          await _store?.complete(purchase);
        } catch (e) {
          debugPrint('[LicenseService] Acknowledging Play purchase failed: $e');
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _storeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _persist(LicenseInfo info) async {
    _currentInfo = info;
    try {
      await _write(_storageKey, info.encode());
    } catch (e) {
      debugPrint('[LicenseService] Error persisting license: $e');
    }

    notifyListeners();
  }

  // ── Offline License Key (Ed25519) ─────────────────────────────────────────

  /// Returns the key's data if [key] is a correctly signed licence key.
  Future<LicenseKeyData?> verifyOfflineKey(String key) =>
      LicenseKeyCodec.verify(key, _publicKey);

  /// Activates an offline license key. Returns true if valid and activated.
  Future<bool> activateOfflineKey(String rawKey) async {
    final data = await verifyOfflineKey(rawKey);
    if (data == null || data.edition != LicenseKeyCodec.editionProLifetime) {
      return false;
    }

    final license = LicenseInfo.proOffline(
      licenseKey: rawKey.trim(),
      activatedAt: DateTime.now(),
      customerReference: data.licenseId,
    );

    await _persist(license);
    return true;
  }

  // ── Revocation / Reset ────────────────────────────────────────────────────

  /// Removes the licence key from this device. The early-adopter mark stays.
  Future<void> revokeLicense() async {
    await _persist(LicenseInfo.free());
  }

  /// Direct override for test suites or QA debugging.
  @visibleForTesting
  void setProForTesting(bool isPro) {
    _currentInfo = isPro
        ? LicenseInfo.proTest(note: 'SetProForTesting')
        : LicenseInfo.free();
    notifyListeners();
  }
}
