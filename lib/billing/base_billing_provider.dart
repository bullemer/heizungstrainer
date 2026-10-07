import 'package:heizungstrainer/utils/number_format.dart';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/billing/billing_storage_keys.dart';
import 'package:heizungstrainer/models/brunata_chart.dart';

/// Base implementation for German sub-metering / heating billing providers
/// (e.g. KALO, Techem, ista, Brunata München, Brunata Hürth, Minol).
///
/// Manages secure local credential storage and generates standard-compliant
/// unterjährige Verbrauchsinformation (uVI according to §6a HeizkostenV).
abstract class BaseBillingProvider implements BillingProvider {
  final FlutterSecureStorage _secureStorage;

  BaseBillingProvider({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  BillingCapabilities get capabilities => const BillingCapabilities(
        supportsCommunityComparison: true,
        supportsMonthlyBreakdown: true,
        supportsExtrapolation: true,
        supportsHotWaterSeparation: true,
      );

  @override
  Future<bool> hasCredentials() async {
    final user = await getUsername();
    final pass = await getPassword();
    return (user != null && user.trim().isNotEmpty) &&
        (pass != null && pass.trim().isNotEmpty);
  }

  @override
  Future<String?> getUsername() async {
    return _secureStorage.read(key: BillingStorageKeys.username(id));
  }

  @override
  Future<String?> getPassword() async {
    return _secureStorage.read(key: BillingStorageKeys.password(id));
  }

  @override
  Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    await _secureStorage.write(
      key: BillingStorageKeys.username(id),
      value: username.trim(),
    );
    await _secureStorage.write(
      key: BillingStorageKeys.password(id),
      value: password,
    );
  }

  @override
  Future<String> getPortalUrl() async {
    final stored = await _secureStorage.read(key: BillingStorageKeys.portalUrl(id));
    if (stored != null && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    return defaultPortalUrl;
  }

  @override
  Future<void> setPortalUrl(String url) async {
    await _secureStorage.write(
      key: BillingStorageKeys.portalUrl(id),
      value: url.trim(),
    );
  }

  @override
  Future<double> getPricePerKwh() async {
    final raw = await _secureStorage.read(key: BillingStorageKeys.pricePerKwh(id));
    if (raw != null) {
      final parsed = double.tryParse(raw);
      if (parsed != null && parsed > 0) return parsed;
    }
    return defaultTariffPrice;
  }

  @override
  Future<void> setPricePerKwh(double price) async {
    await _secureStorage.write(
      key: BillingStorageKeys.pricePerKwh(id),
      value: price.fixed(4),
    );
  }

  /// Default reference price for this provider/region.
  double get defaultTariffPrice => 0.128;

  /// Helper to generate standardized, high-fidelity uVI monthly charts.
  List<BrunataChart> buildStandardUviCharts({
    required String providerShortName,
    required List<double> monthlyHeatingActual,
    required List<double> monthlyHeatingPrevious,
    required List<double> monthlyHeatingBuildingAvg,
    required List<double> monthlyWarmWaterActual,
    required List<double> monthlyWarmWaterBuildingAvg,
    List<bool>? heatingExtrapolatedFlags,
  }) {
    const categories = [
      'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
    ];

    final extrapolated = heatingExtrapolatedFlags ??
        const [
          false, false, false, false, false, false,
          false, false, true, true, true, true,
        ];

    return [
      BrunataChart(
        source: '${id}_month_heizung',
        title: '$providerShortName Monatsvergleich Heizung',
        subtitle: 'Aktuelle Periode vs. Vorjahr (uVI)',
        unit: 'kWh',
        categories: categories,
        series: [
          BrunataChartSeries(
            name: 'Aktuell 2025/2026',
            values: monthlyHeatingActual,
            extrapolated: extrapolated,
          ),
          BrunataChartSeries(
            name: 'Vorjahr 2024/2025',
            values: monthlyHeatingPrevious,
            extrapolated: const [
              false, false, false, false, false, false,
              false, false, false, false, false, false,
            ],
          ),
        ],
      ),
      BrunataChart(
        source: '${id}_building_heizung',
        title: '$providerShortName Liegenschafts-Vergleich Heizung',
        subtitle: 'Verbrauch im Vergleich zum Gebäude-Durchschnitt',
        unit: 'kWh',
        categories: categories,
        series: [
          BrunataChartSeries(
            name: 'Meine Nutzungseinheit',
            values: monthlyHeatingActual,
            extrapolated: extrapolated,
          ),
          BrunataChartSeries(
            name: 'Liegenschafts-Mittel',
            values: monthlyHeatingBuildingAvg,
            extrapolated: const [
              false, false, false, false, false, false,
              false, false, false, false, false, false,
            ],
          ),
        ],
      ),
      BrunataChart(
        source: '${id}_warmwasser',
        title: '$providerShortName Warmwasser & Trinkwassererwärmung',
        subtitle: 'Monatlicher Warmwasserverbrauch vs. Liegenschaft',
        unit: 'kWh',
        categories: categories,
        series: [
          BrunataChartSeries(
            name: 'Meine Wohnung',
            values: monthlyWarmWaterActual,
            extrapolated: const [
              false, false, false, false, false, false,
              false, false, false, false, false, false,
            ],
          ),
          BrunataChartSeries(
            name: 'Liegenschafts-Schnitt',
            values: monthlyWarmWaterBuildingAvg,
            extrapolated: const [
              false, false, false, false, false, false,
              false, false, false, false, false, false,
            ],
          ),
        ],
      ),
    ];
  }
}
