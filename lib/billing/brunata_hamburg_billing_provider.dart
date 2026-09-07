import 'dart:async';

import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/services/brunata_local_scraper_service.dart';

/// Concrete adapter for Brunata Hamburg billing portal integration.
class BrunataHamburgBillingProvider implements BillingProvider {
  final BrunataLocalScraperService _scraper;

  BrunataHamburgBillingProvider({BrunataLocalScraperService? scraper})
      : _scraper = scraper ?? BrunataLocalScraperService();

  @override
  String get id => 'brunata_hamburg';

  @override
  String get displayName => 'Brunata Hamburg';

  @override
  String get organization => 'Brunata Wärmemessdienst Hamburg';

  @override
  BillingAuthType get authType => BillingAuthType.portalScraper;

  @override
  BillingCapabilities get capabilities => const BillingCapabilities(
        supportsCommunityComparison: true,
        supportsMonthlyBreakdown: true,
        supportsExtrapolation: true,
        supportsHotWaterSeparation: true,
      );

  @override
  String get defaultPortalUrl => BrunataLocalScraperService.defaultPortalUrl;

  @override
  Future<String> getPortalUrl() => _scraper.getPortalUrl();

  @override
  Future<void> setPortalUrl(String url) => _scraper.savePortalUrl(url);

  @override
  Future<String?> getUsername() => _scraper.getUsername();

  @override
  Future<String?> getPassword() => _scraper.getPassword();

  @override
  Future<bool> hasCredentials() => _scraper.hasCredentials();

  @override
  Future<void> saveCredentials({
    required String username,
    required String password,
  }) =>
      _scraper.saveCredentials(username: username, password: password);

  @override
  Future<double> getPricePerKwh() => _scraper.getPricePerKwh();

  @override
  Future<void> setPricePerKwh(double price) => _scraper.savePricePerKwh(price);

  @override
  Future<BillingSyncResult> syncData() async {
    final result = await _scraper.syncFromPortal();
    if (result.success && result.data != null) {
      return BillingSyncResult.ok(result.data!);
    }
    return BillingSyncResult.error(
      result.errorMessage ?? 'Unbekannter Synchronisationsfehler',
    );
  }
}
