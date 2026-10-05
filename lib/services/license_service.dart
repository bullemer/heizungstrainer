import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/services/license_key.dart';

/// Central licensing and entitlement service for Heizungstrainer.
///
/// Pro is unlocked with an offline licence key signed with Ed25519 (see
/// [LicenseKeyCodec]). The app only contains the public key, so keys can be
/// checked without internet but not forged from the APK. The stored licence is
/// re-verified on every start, so editing the stored record doesn't unlock Pro.
class LicenseService extends ChangeNotifier {
  static const String _storageKey = 'ecl_license_info';

  final FlutterSecureStorage? _secureStorage;
  final Map<String, String>? _inMemoryStorage;
  final List<int> _publicKey;

  LicenseInfo _currentInfo;
  bool _isInitialized = false;

  LicenseService({
    FlutterSecureStorage? secureStorage,
    Map<String, String>? inMemoryStorage,
    LicenseTier? initialTier,
    @visibleForTesting List<int>? publicKey,
  })  : _publicKey = publicKey ?? LicenseKeyCodec.productionPublicKey,
        _secureStorage = inMemoryStorage != null
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
        if (loaded != null && loaded.isPro) {
          // Only a stored key that still verifies counts; anything else (old
          // HMAC/demo keys, simulated purchases, edited records) falls back to Free.
          final key = loaded.source == LicenseSource.offlineKey ? loaded.licenseKey : null;
          if (key != null && await verifyOfflineKey(key) != null) {
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

  /// Removes the licence from this device and returns to the Free tier.
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
