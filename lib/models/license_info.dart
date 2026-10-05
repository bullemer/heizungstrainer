import 'dart:convert';

/// Represents the tier/level of the user's license.
enum LicenseTier {
  free,
  pro,
}

/// The origin of how the license was acquired/activated.
enum LicenseSource {
  none,
  offlineKey,
  inAppPurchase,
  testOverride,
}

/// Encapsulates the user's license entitlements, source, and activation details.
class LicenseInfo {
  final LicenseTier tier;
  final LicenseSource source;
  final String? licenseKey;
  final String? purchaseId;
  final String? productId;
  final DateTime? activatedAt;
  final String? customerReference;
  final String? note;

  const LicenseInfo({
    required this.tier,
    required this.source,
    this.licenseKey,
    this.purchaseId,
    this.productId,
    this.activatedAt,
    this.customerReference,
    this.note,
  });

  /// True if the user has unlocked Pro features.
  bool get isPro => tier == LicenseTier.pro;

  /// Default free license state.
  factory LicenseInfo.free() {
    return const LicenseInfo(
      tier: LicenseTier.free,
      source: LicenseSource.none,
    );
  }

  /// Pro license activated via an offline cryptographic key (e.g. website purchase).
  factory LicenseInfo.proOffline({
    required String licenseKey,
    DateTime? activatedAt,
    String? customerReference,
  }) {
    return LicenseInfo(
      tier: LicenseTier.pro,
      source: LicenseSource.offlineKey,
      licenseKey: licenseKey,
      activatedAt: activatedAt ?? DateTime.now(),
      customerReference: customerReference,
      note: 'Offline-Lizenzschlüssel (heizungstrainer.de)',
    );
  }

  /// Test or debug override for development.
  factory LicenseInfo.proTest({String note = 'Entwickler-Override'}) {
    return LicenseInfo(
      tier: LicenseTier.pro,
      source: LicenseSource.testOverride,
      activatedAt: DateTime.now(),
      note: note,
    );
  }

  LicenseInfo copyWith({
    LicenseTier? tier,
    LicenseSource? source,
    String? licenseKey,
    String? purchaseId,
    String? productId,
    DateTime? activatedAt,
    String? customerReference,
    String? note,
  }) {
    return LicenseInfo(
      tier: tier ?? this.tier,
      source: source ?? this.source,
      licenseKey: licenseKey ?? this.licenseKey,
      purchaseId: purchaseId ?? this.purchaseId,
      productId: productId ?? this.productId,
      activatedAt: activatedAt ?? this.activatedAt,
      customerReference: customerReference ?? this.customerReference,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tier': tier.name,
      'source': source.name,
      'licenseKey': licenseKey,
      'purchaseId': purchaseId,
      'productId': productId,
      'activatedAt': activatedAt?.toIso8601String(),
      'customerReference': customerReference,
      'note': note,
    };
  }

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    return LicenseInfo(
      tier: LicenseTier.values.firstWhere(
        (e) => e.name == json['tier'],
        orElse: () => LicenseTier.free,
      ),
      source: LicenseSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => LicenseSource.none,
      ),
      licenseKey: json['licenseKey'] as String?,
      purchaseId: json['purchaseId'] as String?,
      productId: json['productId'] as String?,
      activatedAt: json['activatedAt'] != null
          ? DateTime.tryParse(json['activatedAt'] as String)
          : null,
      customerReference: json['customerReference'] as String?,
      note: json['note'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static LicenseInfo? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return LicenseInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
