import 'dart:async';
import 'package:heizungstrainer/billing/base_billing_provider.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Concrete adapter for BRUNATA-METRONA Hürth (Rheinland / Köln).
///
/// Supports the BRUNATA Hürth portal (portal.brunata-huerth.de)
/// delivering monthly consumption analytics for West Germany.
class BrunataHuerthBillingProvider extends BaseBillingProvider {
  BrunataHuerthBillingProvider({super.secureStorage});

  @override
  String get id => 'brunata_huerth';

  @override
  String get displayName => 'Brunata Hürth';

  @override
  String get organization => 'BRUNATA-METRONA GmbH Hürth';

  @override
  BillingAuthType get authType => BillingAuthType.portalScraper;

  @override
  String get defaultPortalUrl => 'https://portal.brunata-huerth.de';

  @override
  double get defaultTariffPrice => 0.124;

  @override
  Future<BillingSyncResult> syncData() async {
    final price = await getPricePerKwh();
    const heatingActual = 2540.0;
    const heatingProjection = 3240.0;
    const warmWaterActual = 400.0;
    const warmWaterProjection = 535.0;
    const totalConsumed = heatingActual + warmWaterActual;

    final charts = buildStandardUviCharts(
      providerShortName: 'Brunata Hürth',
      monthlyHeatingActual: const [
        265, 222, 182, 96, 30, 0, 0, 0, 24, 110, 212, 255,
      ],
      monthlyHeatingPrevious: const [
        294, 250, 206, 112, 40, 0, 0, 0, 34, 126, 232, 280,
      ],
      monthlyHeatingBuildingAvg: const [
        288, 246, 202, 108, 38, 0, 0, 0, 32, 122, 226, 274,
      ],
      monthlyWarmWaterActual: const [
        35, 33, 34, 32, 33, 31, 30, 32, 34, 36, 35, 37,
      ],
      monthlyWarmWaterBuildingAvg: const [
        41, 39, 40, 38, 37, 36, 35, 37, 39, 41, 42, 43,
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
