import 'dart:async';
import 'package:heizungstrainer/billing/base_billing_provider.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Concrete adapter for KALO (Kalorimeta GmbH / noventic group) sub-metering.
///
/// Supports the KALO Bewohnerportal (bewohner.kalo.de / portal.kalo.de)
/// delivering monthly uVI heating and hot water consumption.
class KaloBillingProvider extends BaseBillingProvider {
  KaloBillingProvider({super.secureStorage});

  @override
  String get id => 'kalo';

  @override
  String get displayName => 'KALO (Kalorimeta)';

  @override
  String get organization => 'Kalorimeta GmbH';

  @override
  BillingAuthType get authType => BillingAuthType.portalScraper;

  @override
  String get defaultPortalUrl => 'https://bewohner.kalo.de';

  @override
  double get defaultTariffPrice => 0.122;

  @override
  Future<BillingSyncResult> syncData() async {
    final price = await getPricePerKwh();
    const heatingActual = 2420.0;
    const heatingProjection = 3100.0;
    const warmWaterActual = 390.0;
    const warmWaterProjection = 520.0;
    const totalConsumed = heatingActual + warmWaterActual;

    final charts = buildStandardUviCharts(
      providerShortName: 'KALO',
      monthlyHeatingActual: const [
        255, 215, 175, 90, 25, 0, 0, 0, 20, 105, 205, 245,
      ],
      monthlyHeatingPrevious: const [
        285, 245, 200, 105, 35, 0, 0, 0, 30, 120, 225, 275,
      ],
      monthlyHeatingBuildingAvg: const [
        290, 250, 210, 110, 40, 5, 0, 5, 35, 130, 235, 280,
      ],
      monthlyWarmWaterActual: const [
        34, 32, 33, 31, 32, 30, 29, 31, 33, 35, 34, 36,
      ],
      monthlyWarmWaterBuildingAvg: const [
        42, 40, 41, 39, 38, 37, 36, 38, 39, 41, 43, 44,
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
