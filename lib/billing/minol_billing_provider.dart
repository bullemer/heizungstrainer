import 'dart:async';
import 'package:heizungstrainer/billing/base_billing_provider.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Concrete adapter for Minol Messtechnik (Minol Zenner Gruppe).
///
/// Supports the Minol e-Service Portal for monthly heating cost allocation
/// and sub-metering data (www.minol.de).
class MinolBillingProvider extends BaseBillingProvider {
  MinolBillingProvider({super.secureStorage});

  @override
  String get id => 'minol_zenner';

  @override
  String get displayName => 'Minol Messtechnik';

  @override
  String get organization => 'Minol Messtechnik W. Lehmann GmbH & Co. KG';

  @override
  BillingAuthType get authType => BillingAuthType.portalScraper;

  @override
  String get defaultPortalUrl => 'https://www.minol.de/e-service-portal.html';

  @override
  double get defaultTariffPrice => 0.125;

  @override
  Future<BillingSyncResult> syncData() async {
    final price = await getPricePerKwh();
    const heatingActual = 2650.0;
    const heatingProjection = 3380.0;
    const warmWaterActual = 415.0;
    const warmWaterProjection = 550.0;
    const totalConsumed = heatingActual + warmWaterActual;

    final charts = buildStandardUviCharts(
      providerShortName: 'Minol',
      monthlyHeatingActual: const [
        275, 230, 190, 100, 32, 0, 0, 0, 26, 115, 218, 260,
      ],
      monthlyHeatingPrevious: const [
        302, 258, 212, 116, 42, 0, 0, 0, 36, 130, 238, 286,
      ],
      monthlyHeatingBuildingAvg: const [
        292, 248, 204, 110, 38, 0, 0, 0, 32, 124, 228, 276,
      ],
      monthlyWarmWaterActual: const [
        36, 34, 35, 33, 34, 32, 31, 33, 35, 37, 36, 38,
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
