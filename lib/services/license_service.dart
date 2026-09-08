import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/license_info.dart';

/// Central licensing and entitlement service for Heizungstrainer.
///
/// Supports two distinct unlock mechanisms:
/// 1. **Offline License Key (Cryptographic HMAC-SHA256)**: 100% Local-First,
///    no internet connection required. Ideal for direct website purchases on heizungstrainer.de.
/// 2. **In-App Purchase (IAP)**: Standard Google Play Billing / Apple StoreKit integration.
class LicenseService extends ChangeNotifier {
  static const String _storageKey = 'ecl_license_info';

  /// Secret salt used for HMAC verification of offline license keys.
  /// (Kept internal for offline verification).
  static const String _offlineSalt = 'ht_ecl310_offline_sec_2026_salt';

  /// Predefined universal test keys for QA and development.
  static const Set<String> _demoKeys = {
    'HT-PRO-DEMO-2026',
    'HTPRO-TEST-KEY-VALID',
    'HT-PRO-DEVELOPER-BYPASS',
  };

  /// Product IDs for app store listings.
  static const String proLifetimeProductId = 'de.heizungstrainer.pro.lifetime';
  static const String proYearlyProductId = 'de.heizungstrainer.pro.yearly';

  final FlutterSecureStorage? _secureStorage;
  final Map<String, String>? _inMemoryStorage;

  LicenseInfo _currentInfo;
  bool _isInitialized = false;

  LicenseService({
    FlutterSecureStorage? secureStorage,
    Map<String, String>? inMemoryStorage,
    LicenseTier? initialTier,
  })  : _secureStorage = inMemoryStorage != null
            ? null
            : (secureStorage ?? const FlutterSecureStorage()),
        _inMemoryStorage = inMemoryStorage,
        _currentInfo = initialTier == LicenseTier.pro
            ? LicenseInfo.proTest(note: 'Initial Test Pro')
            : LicenseInfo.free();

  /// Current license state.
  LicenseInfo get currentInfo => _currentInfo;

  /// Current tier (free or pro).
  LicenseTier get currentTier => _currentInfo.tier;

  /// Whether the user has unlocked Pro features.
  bool get isPro => _currentInfo.isPro;

  /// Whether the service has completed loading from secure storage.
  bool get isInitialized => _isInitialized;

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
      String? raw;
      if (_inMemoryStorage != null) {
        raw = _inMemoryStorage[_storageKey];
      } else if (_secureStorage != null) {
        raw = await _secureStorage!.read(key: _storageKey);
      }

      if (raw != null && raw.isNotEmpty) {
        final loaded = LicenseInfo.decode(raw);
        if (loaded != null) {
          _currentInfo = loaded;
        }
      }
    } catch (e) {
      debugPrint('[LicenseService] Error loading stored license: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _persist(LicenseInfo info) async {
    _currentInfo = info;
    final encoded = info.encode();

    if (_inMemoryStorage != null) {
      _inMemoryStorage[_storageKey] = encoded;
    } else {
      try {
        await _secureStorage!.write(key: _storageKey, value: encoded);
      } catch (e) {
        debugPrint('[LicenseService] Error persisting license: $e');
      }
    }

    notifyListeners();
  }

  // ── Offline License Key Engine (HMAC-SHA256) ──────────────────────────────

  /// Normalizes any input key (strips whitespace, dashes, to uppercase).
  static String normalizeKey(String key) {
    return key.replaceAll('-', '').replaceAll(' ', '').toUpperCase().trim();
  }

  /// Verifies whether an offline license key is authentic and correctly signed.
  ///
  /// Expected key format: `HTPRO-<8 CHAR PAYLOAD>-<8 CHAR HMAC>`
  /// e.g. `HTPRO-A8C2-91B4-E4F0-77A1`
  static bool verifyOfflineKey(String key) {
    final trimmed = key.trim().toUpperCase();
    if (_demoKeys.contains(trimmed)) return true;

    final normalized = normalizeKey(key);
    // Must start with HTPRO and have at least 16 chars following (8 payload + 8 hmac)
    if (!normalized.startsWith('HTPRO') || normalized.length != 21) {
      return false;
    }

    final payload = normalized.substring(5, 13); // 8 chars
    final givenSignature = normalized.substring(13, 21); // 8 chars

    final expectedSignature = _computeHmac(payload);
    return expectedSignature == givenSignature;
  }

  /// Generates a valid, cryptographically signed Pro license key.
  ///
  /// Can be executed in admin scripts, the backoffice, or for testing.
  /// Returns a formatted key: `HTPRO-XXXX-XXXX-XXXX-XXXX`
  static String generateKey({String? customPayload}) {
    final random = Random.secure();
    final payload = customPayload != null && customPayload.length == 8
        ? customPayload.toUpperCase()
        : List.generate(8, (_) => random.nextInt(16).toRadixString(16).toUpperCase()).join();

    final signature = _computeHmac(payload);

    // Format as HTPRO-XXXX-XXXX-XXXX-XXXX
    final p1 = payload.substring(0, 4);
    final p2 = payload.substring(4, 8);
    final s1 = signature.substring(0, 4);
    final s2 = signature.substring(4, 8);

    return 'HTPRO-$p1-$p2-$s1-$s2';
  }

  static String _computeHmac(String payload) {
    final hmac = Hmac(sha256, utf8.encode(_offlineSalt));
    final digest = hmac.convert(utf8.encode(payload));
    return digest.toString().substring(0, 8).toUpperCase();
  }

  /// Activates an offline license key. Returns true if valid and activated.
  Future<bool> activateOfflineKey(String rawKey) async {
    if (!verifyOfflineKey(rawKey)) {
      return false;
    }

    final license = LicenseInfo.proOffline(
      licenseKey: rawKey.trim().toUpperCase(),
      activatedAt: DateTime.now(),
    );

    await _persist(license);
    return true;
  }

  // ── In-App Purchase (IAP) Engine ──────────────────────────────────────────

  /// Activates Pro tier from a successful Google Play / Apple StoreKit purchase.
  Future<bool> activateInAppPurchase({
    required String purchaseId,
    required String productId,
  }) async {
    final license = LicenseInfo.proInApp(
      purchaseId: purchaseId,
      productId: productId,
      activatedAt: DateTime.now(),
    );

    await _persist(license);
    return true;
  }

  /// Restores previous app store purchases if available.
  Future<bool> restorePurchases() async {
    // In production with in_app_purchase package, this contacts Google Play / Apple StoreKit.
    // If a cached or stored purchase exists, re-affirm it.
    if (_currentInfo.source == LicenseSource.inAppPurchase && _currentInfo.isPro) {
      return true;
    }
    // If no active store purchase is found:
    return false;
  }

  // ── Revocation / Reset ────────────────────────────────────────────────────

  /// Revokes any Pro license and resets back to the free tier (useful for testing).
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
