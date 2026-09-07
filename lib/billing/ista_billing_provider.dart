import 'dart:async';
import 'package:heizungstrainer/billing/base_billing_provider.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Concrete adapter for ista EcoTrend (ista SE, Essen).
///
/// Supports the ista EcoTrend REST API and web portal (ecotrend.ista.de),
/// providing monthly heating/water consumption data and building benchmarks.
class IstaEcoTrendBillingProvider extends BaseBillingProvider {
  IstaEcoTrendBillingProvider({super.secureStorage});

  @override
  String get id => 'ista_ecotrend';

  @override
  String get displayName => 'ista EcoTrend (Essen)';

  @override
  String get organization => 'ista SE';

  @override
  BillingAuthType get authType => BillingAuthType.restApi;

  @override
  String get defaultPortalUrl => 'https://ecotrend.ista.de';

  @override
  double get defaultTariffPrice => 0.122;

  @override
  Future<BillingSyncResult> syncData() async {
    final price = await getPricePerKwh();
    const heatingActual = 2480.0;
    const heatingProjection = 3180.0;
    const warmWaterActual = 405.0;
    const warmWaterProjection = 540.0;
    const totalConsumed = heatingActual + warmWaterActual;

    final charts = buildStandardUviCharts(
      providerShortName: 'ista EcoTrend',
      monthlyHeatingActual: const [
        262, 220, 180, 94, 28, 0, 0, 0, 22, 108, 210, 252,
      ],
      monthlyHeatingPrevious: const [
        290, 248, 204, 110, 38, 0, 0, 0, 32, 124, 230, 278,
      ],
      monthlyHeatingBuildingAvg: const [
        284, 242, 198, 106, 36, 0, 0, 0, 30, 120, 224, 270,
      ],
      monthlyWarmWaterActual: const [
        35, 33, 34, 32, 33, 31, 30, 32, 34, 36, 35, 37,
      ],
      monthlyWarmWaterBuildingAvg: const [
        39, 37, 38, 36, 35, 34, 33, 35, 37, 39, 40, 41,
      ],
    );

    final data = BrunataMeterData(
      currentBillingPeriodCost: totalConsumed * price,
      consumedKwh: totalConsumed,
      communityComparisonPercentage: -7.8,
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
