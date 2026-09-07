/// Data model for Brunata cost portal integration.
///
/// Represents metered heating cost and consumption data from the
/// Brunata billing portal, used for cost visualization and
/// community efficiency comparisons.
library;

import 'package:heizungstrainer/models/brunata_chart.dart';

/// A snapshot of the user's current billing period data from
/// the Brunata metering portal.
class BrunataMeterData {
  /// Current billing period heating cost in Euros (estimated from [pricePerKwh]).
  final double currentBillingPeriodCost;

  /// Total consumed kilowatt-hours in the current period (YTD actual heating).
  final double consumedKwh;

  /// Percentage comparison against the anonymized community average.
  /// Positive = above average (worse), negative = below average (better).
  /// Example: +15.0 means 15% above the community average.
  final double communityComparisonPercentage;

  /// Billing period start date.
  final DateTime periodStart;

  /// Billing period end date.
  final DateTime periodEnd;

  /// Price per kWh used to estimate all costs.
  final double pricePerKwh;

  /// Year-to-date actual / full-year projection per medium (kWh).
  final double heatingYtdActual;
  final double heatingProjection;
  final double warmWaterYtdActual;
  final double warmWaterProjection;

  /// All scraped charts (monthly Heizung/Warmwasser, YTD overview, building
  /// comparison), preserved for the detail drill-down.
  final List<BrunataChart> charts;

  const BrunataMeterData({
    required this.currentBillingPeriodCost,
    required this.consumedKwh,
    required this.communityComparisonPercentage,
    required this.periodStart,
    required this.periodEnd,
    this.pricePerKwh = 0.10,
    this.heatingYtdActual = 0,
    this.heatingProjection = 0,
    this.warmWaterYtdActual = 0,
    this.warmWaterProjection = 0,
    this.charts = const [],
  });

  /// Whether the user's consumption is above the community average.
  bool get isAboveCommunityAverage => communityComparisonPercentage > 0;

  /// Cost per kWh in the current period.
  double get costPerKwh =>
      consumedKwh > 0 ? currentBillingPeriodCost / consumedKwh : 0;

  /// Whether detailed chart data is available for the drill-down view.
  bool get hasDetail => charts.isNotEmpty;

  /// Returns a copy with cost fields recomputed for a new tariff.
  BrunataMeterData copyWithPrice(double newPrice) {
    return BrunataMeterData(
      currentBillingPeriodCost: consumedKwh * newPrice,
      consumedKwh: consumedKwh,
      communityComparisonPercentage: communityComparisonPercentage,
      periodStart: periodStart,
      periodEnd: periodEnd,
      pricePerKwh: newPrice,
      heatingYtdActual: heatingYtdActual,
      heatingProjection: heatingProjection,
      warmWaterYtdActual: warmWaterYtdActual,
      warmWaterProjection: warmWaterProjection,
      charts: charts,
    );
  }

  /// Create demo/placeholder data for UI development.
  /// Will be replaced with actual Brunata API integration.
  factory BrunataMeterData.demo() {
    final now = DateTime.now();
    return BrunataMeterData(
      currentBillingPeriodCost: 187.50,
      consumedKwh: 1450,
      communityComparisonPercentage: 23.5,
      periodStart: DateTime(now.year, now.month, 1),
      periodEnd: DateTime(now.year, now.month + 1, 0),
    );
  }
}
