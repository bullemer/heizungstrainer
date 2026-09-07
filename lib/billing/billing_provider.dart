import 'dart:async';

import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Authentication and data retrieval mechanism used by a billing provider.
enum BillingAuthType {
  portalScraper,
  restApi,
  oauth2,
  fileImport,
}

/// Feature set of a billing/metering service.
class BillingCapabilities {
  final bool supportsCommunityComparison;
  final bool supportsMonthlyBreakdown;
  final bool supportsExtrapolation;
  final bool supportsHotWaterSeparation;

  const BillingCapabilities({
    this.supportsCommunityComparison = true,
    this.supportsMonthlyBreakdown = true,
    this.supportsExtrapolation = true,
    this.supportsHotWaterSeparation = true,
  });
}

/// Universal standardized billing result.
class BillingSyncResult {
  final bool success;
  final BrunataMeterData? data;
  final String? errorMessage;

  const BillingSyncResult({
    required this.success,
    this.data,
    this.errorMessage,
  });

  factory BillingSyncResult.ok(BrunataMeterData data) =>
      BillingSyncResult(success: true, data: data);

  factory BillingSyncResult.error(String message) =>
      BillingSyncResult(success: false, errorMessage: message);
}

/// Abstract interface for all heating cost allocation and metering providers
/// (e.g., Brunata Hamburg, Techem, ista, Minol, Kalo).
abstract class BillingProvider {
  /// Unique identifier (e.g. 'brunata_hamburg', 'techem').
  String get id;

  /// Display name of the provider (e.g. 'Brunata Hamburg', 'Techem Smart System').
  String get displayName;

  /// Service provider organization (e.g. 'Brunata-Metrona', 'Techem Energy Services').
  String get organization;

  /// Authentication type required.
  BillingAuthType get authType;

  /// Provider feature capabilities.
  BillingCapabilities get capabilities;

  /// Checks whether valid credentials or tokens exist.
  Future<bool> hasCredentials();

  /// Saves login credentials or configuration.
  Future<void> saveCredentials({
    required String username,
    required String password,
  });

  /// Configured tariff price per kWh.
  Future<double> getPricePerKwh();

  /// Persists the tariff price per kWh.
  Future<void> setPricePerKwh(double price);

  /// Default portal or API URL.
  String get defaultPortalUrl => '';

  /// Currently configured portal URL (or default).
  Future<String> getPortalUrl() async => defaultPortalUrl;

  /// Saves a custom portal URL if supported.
  Future<void> setPortalUrl(String url) async {}

  /// Retrieves stored username / customer number.
  Future<String?> getUsername() async => null;

  /// Retrieves stored password.
  Future<String?> getPassword() async => null;

  /// Synchronizes meter and consumption data from the provider.
  Future<BillingSyncResult> syncData();
}
