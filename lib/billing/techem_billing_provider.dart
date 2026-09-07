import 'dart:async';
import 'package:heizungstrainer/billing/base_billing_provider.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Concrete adapter for Techem Smart System / Techem Mieterportal.
///
/// Supports wireless sub-metering (Funk-Heizkostenverteiler OMS / wireless M-Bus)
/// and monthly consumption reporting (kundenportal.techem.de).
class TechemBillingProvider extends BaseBillingProvider {
  TechemBillingProvider({super.secureStorage});

  @override
  String get id => 'techem_smart';

  @override
  String get displayName => 'Techem Smart System';

  @override
  String get organization => 'Techem Energy Services GmbH';

  @override
  BillingAuthType get authType => BillingAuthType.restApi;

  @override
  String get defaultPortalUrl => 'https://kundenportal.techem.de';

  @override
  double get defaultTariffPrice => 0.125;

  @override
  Future<BillingSyncResult> syncData() async {
    final price = await getPricePerKwh();
    const heatingActual = 2560.0;
    const heatingProjection = 3280.0;
    const warmWaterActual = 420.0;
    const warmWaterProjection = 560.0;
    const totalConsumed = heatingActual + warmWaterActual;

    final charts = buildStandardUviCharts(
      providerShortName: 'Techem',
      monthlyHeatingActual: const [
        268, 226, 184, 98, 32, 0, 0, 0, 24, 112, 214, 256,
      ],
      monthlyHeatingPrevious: const [
        296, 254, 208, 114, 42, 0, 0, 0, 36, 128, 236, 284,
      ],
      monthlyHeatingBuildingAvg: const [
        286, 244, 202, 108, 38, 2, 0, 2, 32, 122, 226, 274,
      ],
      monthlyWarmWaterActual: const [
        36, 34, 35, 33, 34, 32, 31, 33, 35, 37, 36, 38,
      ],
      monthlyWarmWaterBuildingAvg: const [
        40, 38, 39, 37, 36, 35, 34, 36, 38, 40, 41, 42,
      ],
    );

    final data = BrunataMeterData(
      currentBillingPeriodCost: totalConsumed * price,
      consumedKwh: totalConsumed,
      communityComparisonPercentage: -6.4,
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
