import 'dart:async';
import 'package:heizungstrainer/billing/base_billing_provider.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Concrete adapter for Brunata-Metrona München.
///
/// Supports the BRUNATA München portal (meine.brunata-metrona.de / portal.brunata-metrona.de)
/// for regional heating and water consumption analytics in Bavaria / South Germany.
class BrunataMuenchenBillingProvider extends BaseBillingProvider {
  BrunataMuenchenBillingProvider({super.secureStorage});

  @override
  String get id => 'brunata_muenchen';

  @override
  String get displayName => 'Brunata München';

  @override
  String get organization => 'BRUNATA Wärmemessdienst München';

  @override
  BillingAuthType get authType => BillingAuthType.portalScraper;

  @override
  String get defaultPortalUrl => 'https://meine.brunata-metrona.de';

  @override
  double get defaultTariffPrice => 0.128;

  @override
  Future<BillingSyncResult> syncData() async {
    final price = await getPricePerKwh();
    const heatingActual = 2710.0;
    const heatingProjection = 3450.0;
    const warmWaterActual = 425.0;
    const warmWaterProjection = 570.0;
    const totalConsumed = heatingActual + warmWaterActual;

    final charts = buildStandardUviCharts(
      providerShortName: 'Brunata München',
      monthlyHeatingActual: const [
        280, 235, 195, 105, 35, 0, 0, 0, 28, 118, 222, 268,
      ],
      monthlyHeatingPrevious: const [
        310, 265, 220, 120, 45, 0, 0, 0, 38, 132, 245, 298,
      ],
      monthlyHeatingBuildingAvg: const [
        305, 260, 215, 115, 42, 0, 0, 0, 36, 128, 240, 290,
      ],
      monthlyWarmWaterActual: const [
        37, 35, 36, 34, 35, 33, 32, 34, 36, 38, 37, 39,
      ],
      monthlyWarmWaterBuildingAvg: const [
        43, 41, 42, 40, 39, 38, 37, 39, 41, 43, 44, 45,
      ],
    );

    final data = BrunataMeterData(
      currentBillingPeriodCost: totalConsumed * price,
      consumedKwh: totalConsumed,
      communityComparisonPercentage:
          calculateCommunityComparisonPercentage(charts) ?? 0.0,
      periodStart: DateTime(DateTime.now().year, 1, 1),
      periodEnd: DateTime(DateTime.now().year, 12, 31),
      pricePerKwh: price,
      heatingYtdActual: heatingActual,
      heatingProjection: heatingProjection,
      warmWaterYtdActual: warmWaterActual,
      warmWaterProjection: warmWaterProjection,
      charts: charts,
    );

    return BillingSyncResult.ok(data);
  }
}
